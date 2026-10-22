# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/file_updater/berry_lockfile_handler"
require "webrick"
require "rubygems/package"
require "zlib"

RSpec.describe Dependabot::NpmAndYarn::FileUpdater::BerryLockfileHandler do
  extend T::Sig

  sig { returns(String) }
  let(:fixture_path) do
    File.join("spec", "fixtures", "projects", "yarn_berry", "security_update", "yarn.lock")
  end

  describe ".update_subdependency" do
    # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) { project_dependency_files("yarn_berry/multiple_brace_expansion_versions") }

    sig { returns(T::Hash[String, String]) }
    let(:existing_resolutions) do
      {
        "brace-expansion" => "npm:^2.0.2",
        "unrelated" => "npm:1.0.0",
        "brace-expansion@npm:^2.0.2" => "npm:2.1.2"
      }
    end
    # rubocop:enable RSpec/ScatteredLet

    before do
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:enable_yarn_berry_conflicting_dependencies).and_return(true)
    end

    it "does not install or read files when the experiment is disabled" do
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:enable_yarn_berry_conflicting_dependencies).and_return(false)
      expect(Dependabot::NpmAndYarn::Helpers).not_to receive(:run_yarn_command)

      expect(
        described_class.update_subdependency(
          yarn_lock: Dependabot::DependencyFile.new(name: "yarn.lock", content: ""),
          dependency: Dependabot::Dependency.new(
            name: "brace-expansion", version: "2.1.2", requirements: [], package_manager: "npm_and_yarn"
          ),
          target_version: "2.1.4",
          install_args: ""
        )
      ).to be_nil
    end

    it "preserves existing resolution precedence and restores the original manifest" do
      allow(Dependabot::NpmAndYarn::Helpers).to receive(:yarn_major_version).and_return(4)
      install_count = 0
      allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_yarn_command) do
        manifest = JSON.parse(File.read("package.json"))
        if install_count.zero?
          expect(manifest.fetch("resolutions").to_a).to eq(
            [
              ["brace-expansion", "npm:2.1.4"],
              ["unrelated", "npm:1.0.0"],
              ["brace-expansion@npm:^2.0.2", "npm:2.1.2"]
            ]
          )
          File.write("yarn.lock", File.read("yarn.lock").gsub("2.1.2", "2.1.4"))
        else
          expect(manifest.fetch("resolutions")).to eq(existing_resolutions)
        end
        install_count += 1
        ""
      end

      files = dependency_files
      Dependabot::SharedHelpers.in_a_temporary_directory do
        files.each { |file| File.write(file.name, T.must(file.content)) }
        manifest = JSON.parse(File.read("package.json")).merge("resolutions" => existing_resolutions)
        original_manifest = JSON.pretty_generate(manifest)
        File.write("package.json", original_manifest)

        result = described_class.update_subdependency(
          yarn_lock: T.must(dependency_files.find { |file| file.name == "yarn.lock" }),
          dependency: Dependabot::Dependency.new(
            name: "brace-expansion", version: "2.1.2", requirements: [], package_manager: "npm_and_yarn"
          ),
          target_version: "2.1.4"
        )

        expect(result).to eq("2.1.4")
        expect(File.read("yarn.lock")).to include("brace-expansion@npm:2.1.4")
        expect(File.read("package.json")).to eq(original_manifest)
        expect(install_count).to eq(2)
      end
    end

    it "updates rewritten incoming requests with real Yarn while preserving earlier parent-specific resolutions" do
      files = project_dependency_files("yarn_berry/rewritten_resolutions")
      versions = %w(1.1.12 2.1.2 5.0.2)
      server = WEBrick::HTTPServer.new(
        Port: 0, BindAddress: "127.0.0.1", Logger: WEBrick::Log.new(File::NULL), AccessLog: []
      )
      registry = "http://127.0.0.1:#{server.config.fetch(:Port)}"
      server.mount_proc("/") do |request, response|
        response.body = if request.path.end_with?(".tgz")
                          version = File.basename(request.path, ".tgz")
                          package_tarball("brace-expansion", version)
                        else
                          JSON.generate(
                            "name" => "brace-expansion",
                            "versions" => versions.to_h do |version|
                              [version, {
                                "name" => "brace-expansion", "version" => version,
                                "dist" => { "tarball" => "#{registry}/#{version}.tgz" }
                              }]
                            end
                          )
                        end
      end
      server_thread = Thread.new { server.start }

      begin
        Dependabot::SharedHelpers.in_a_temporary_directory do
          files.each do |file|
            FileUtils.mkdir_p(File.dirname(file.name))
            File.write(file.name, T.must(file.content))
          end
          yarn_path = File.expand_path(
            "../../../fixtures/projects/yarn_berry/simple_node_modules/.yarn/releases/yarn-3.3.0.cjs",
            __dir__
          )
          File.write(
            ".yarnrc.yml",
            YAML.dump(
              "yarnPath" => yarn_path,
              "npmRegistryServer" => registry,
              "unsafeHttpWhitelist" => ["127.0.0.1"]
            )
          )
          Dependabot::NpmAndYarn::Helpers.run_yarn_command("install --mode=update-lockfile")
          lockfile = Dependabot::DependencyFile.new(name: "yarn.lock", content: File.read("yarn.lock"))
          original_manifest = File.read("package.json")
          expect(T.must(lockfile.content)).to include("brace-expansion@npm:^2.0.2")
          expect(T.must(lockfile.content)).to include("brace-expansion@npm:^5.0.2")
          expect(T.must(lockfile.content)).not_to include("brace-expansion@npm:^2.0.0")
          versions << "2.1.4"

          expect(
            described_class.update_subdependency(
              yarn_lock: lockfile,
              dependency: Dependabot::Dependency.new(
                name: "brace-expansion", version: "2.1.2", requirements: [], package_manager: "npm_and_yarn"
              ),
              target_version: "2.1.4"
            )
          ).to eq("2.1.4")

          updated_file = lockfile.dup
          updated_file.content = File.read("yarn.lock")
          expect(
            Dependabot::NpmAndYarn::FileParser::YarnLock.new(updated_file)
                        .versions_by_requirement("brace-expansion")
          ).to eq(
            "brace-expansion@npm:^1.1.7" => "1.1.12",
            "brace-expansion@npm:^2.0.2" => "2.1.4",
            "brace-expansion@npm:^5.0.2" => "5.0.2"
          )
          expect(File.read("package.json")).to eq(original_manifest)
        end
      ensure
        server.shutdown
        server_thread.join
      end
    end

    sig { params(name: String, version: String).returns(String) }
    def package_tarball(name, version)
      content = JSON.generate("name" => name, "version" => version)
      archive = StringIO.new
      Gem::Package::TarWriter.new(archive) do |tar|
        tar.add_file_simple("package/package.json", 0o644, content.bytesize) { |file| file.write(content) }
      end
      Zlib.gzip(archive.string)
    end
  end

  describe ".parse" do
    it "parses a valid yarn berry lockfile" do
      parsed = described_class.parse(fixture_path)
      expect(parsed).to be_a(Hash)
      expect(T.must(parsed).keys).to include("__metadata")
    end

    it "returns nil for a non-existent file" do
      expect(described_class.parse("nonexistent.lock")).to be_nil
    end
  end

  describe ".split_descriptor" do
    it "splits a simple descriptor" do
      name, version = described_class.split_descriptor("axios@npm:^1.15.0")
      expect(name).to eq("axios")
      expect(version).to eq("npm:^1.15.0")
    end

    it "splits a scoped package descriptor" do
      name, version = described_class.split_descriptor("@scope/pkg@npm:^1.0.0")
      expect(name).to eq("@scope/pkg")
      expect(version).to eq("npm:^1.0.0")
    end

    it "handles descriptor without version" do
      name, version = described_class.split_descriptor("axios")
      expect(name).to eq("axios")
      expect(version).to be_nil
    end

    it "handles scoped package without version" do
      name, version = described_class.split_descriptor("@scope/pkg")
      expect(name).to eq("@scope/pkg")
      expect(version).to be_nil
    end
  end

  describe ".version_matches?" do
    sig { returns(T::Hash[String, T::Hash[String, T.any(String, Integer)]]) }
    let(:parsed) do
      {
        "axios@npm:^1.15.0" => { "version" => "1.15.0", "resolution" => "axios@npm:1.15.0" },
        "@scope/pkg@npm:^2.0.0" => { "version" => "2.1.0", "resolution" => "@scope/pkg@npm:2.1.0" },
        "__metadata" => { "version" => 8 }
      }
    end

    it "returns true when version matches" do
      expect(described_class.version_matches?(parsed, "axios", "1.15.0")).to be true
    end

    it "returns false when version differs" do
      expect(described_class.version_matches?(parsed, "axios", "1.15.2")).to be false
    end

    it "returns false for unknown dependency" do
      expect(described_class.version_matches?(parsed, "unknown-pkg", "1.0.0")).to be false
    end

    it "handles scoped packages" do
      expect(described_class.version_matches?(parsed, "@scope/pkg", "2.1.0")).to be true
      expect(described_class.version_matches?(parsed, "@scope/pkg", "2.0.0")).to be false
    end

    context "with composite keys" do
      sig { returns(T::Hash[String, T::Hash[String, T.any(String, Integer)]]) }
      let(:parsed) do
        {
          "lodash@npm:1.3.1, lodash@npm:^1.3.1" => { "version" => "1.3.1" }
        }
      end

      it "matches composite keys" do
        expect(described_class.version_matches?(parsed, "lodash", "1.3.1")).to be true
        expect(described_class.version_matches?(parsed, "lodash", "1.3.0")).to be false
      end
    end
  end

  describe ".find_exact_key" do
    sig { returns(T::Hash[String, T::Hash[String, T.any(String, Integer)]]) }
    let(:parsed) do
      {
        "axios@npm:1.15.2" => { "version" => "1.15.2" },
        "lodash@npm:^1.3.1" => { "version" => "1.3.1" },
        "@scope/pkg@npm:2.0.0" => { "version" => "2.0.0" }
      }
    end

    it "finds exact version key" do
      expect(described_class.find_exact_key(parsed, "axios", "1.15.2")).to eq("axios@npm:1.15.2")
    end

    it "finds scoped package key" do
      expect(described_class.find_exact_key(parsed, "@scope/pkg", "2.0.0")).to eq("@scope/pkg@npm:2.0.0")
    end

    it "returns nil when not found" do
      expect(described_class.find_exact_key(parsed, "axios", "9.9.9")).to be_nil
    end

    it "does not match range keys" do
      expect(described_class.find_exact_key(parsed, "lodash", "1.3")).to be_nil
    end
  end

  describe ".extract_protocol" do
    it "extracts npm protocol" do
      expect(described_class.extract_protocol("axios@npm:1.15.2", "axios")).to eq("npm:")
    end

    it "extracts protocol from scoped package" do
      expect(described_class.extract_protocol("@scope/pkg@npm:^1.0.0", "@scope/pkg")).to eq("npm:")
    end

    it "extracts protocol from composite key" do
      expect(described_class.extract_protocol("lodash@npm:1.3.1, lodash@npm:^1.3.1", "lodash")).to eq("npm:")
    end

    it "returns empty string when no protocol" do
      expect(described_class.extract_protocol("axios@1.15.2", "axios")).to eq("")
    end
  end

  describe ".replace_declaration" do
    # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
    sig { returns(String) }
    let(:tmp_dir) { Dir.mktmpdir }
    sig { returns(String) }
    let(:lockfile_path) { File.join(tmp_dir, "yarn.lock") }
    # rubocop:enable RSpec/ScatteredLet

    after { FileUtils.rm_rf(tmp_dir) }

    it "replaces exact descriptor with range" do
      File.write(lockfile_path, <<~YAML)
        "axios@npm:1.15.2":
          version: 1.15.2
          resolution: "axios@npm:1.15.2"
          checksum: abc123
      YAML

      described_class.replace_declaration(lockfile_path, "axios", "1.15.2", "^1.15.2")

      content = File.read(lockfile_path)
      expect(content).to include('"axios@npm:^1.15.2":')
      expect(content).not_to include('"axios@npm:1.15.2":')
      expect(content).to include("version: 1.15.2")
      expect(content).to include('resolution: "axios@npm:1.15.2"')
    end

    it "handles tilde ranges" do
      File.write(lockfile_path, <<~YAML)
        "lodash@npm:1.3.1":
          version: 1.3.1
          resolution: "lodash@npm:1.3.1"
      YAML

      described_class.replace_declaration(lockfile_path, "lodash", "1.3.1", "~1.3.1")

      content = File.read(lockfile_path)
      expect(content).to include('"lodash@npm:~1.3.1":')
    end

    it "handles scoped packages" do
      File.write(lockfile_path, <<~YAML)
        "@scope/pkg@npm:2.0.0":
          version: 2.0.0
          resolution: "@scope/pkg@npm:2.0.0"
      YAML

      described_class.replace_declaration(lockfile_path, "@scope/pkg", "2.0.0", "^2.0.0")

      content = File.read(lockfile_path)
      expect(content).to include('"@scope/pkg@npm:^2.0.0":')
    end

    it "does nothing when exact key not found" do
      original = <<~YAML
        "axios@npm:^1.15.0":
          version: 1.15.0
      YAML
      File.write(lockfile_path, original)

      described_class.replace_declaration(lockfile_path, "axios", "1.15.2", "^1.15.2")

      expect(File.read(lockfile_path)).to eq(original)
    end
  end
end
