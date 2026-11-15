# typed: false
# frozen_string_literal: true

require "spec_helper"
require "toml-rb"
require "dependabot/mise"

RSpec.describe Dependabot::Mise::FileUpdater do
  describe "updating mise lockfiles" do
    let(:manifests) { { "mise.toml" => "[tools]\nnode = '20.0.0'\nterraform = '1.9.0'\n" } }
    let(:lockfiles) { lock(manifests) }
    let(:dependency_files) do
      manifests.merge(lockfiles).map { |name, content| Dependabot::DependencyFile.new(name: name, content: content) }
    end
    let(:tool) { "node" }
    let(:updates) { { "mise.toml" => %w(20.0.0 20.1.0) } }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: tool,
        version: updates.values.map(&:last).min,
        previous_version: updates.values.map(&:first).min,
        package_manager: "mise",
        requirements: updates.map { |file, (_, to)| requirement(file, to) },
        previous_requirements: updates.map { |file, (from, _)| requirement(file, from) }
      )
    end
    let(:changes) do
      described_class.new(dependency_files: dependency_files, dependencies: [dependency], credentials: [])
                     .updated_dependency_files
    end
    let(:updated_files) { changes.to_h { |file| [file.name, file.content] } }
    let(:sidecar_names) { %w(aube-lock.yaml package.json) }

    # Builds the starting lockfiles, and any sidecar files, with mise itself for one platform.
    def lock(files)
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          files.each do |name, content|
            FileUtils.mkdir_p(File.dirname(name))
            File.write(name, content)
          end
          Dependabot::SharedHelpers.run_shell_command(
            ["mise", "lock", "--platform", "linux-x64"],
            stderr_to_stdout: false,
            env: { "MISE_YES" => "1", "MISE_SAFE" => "1", "MISE_OVERRIDE_CONFIG_FILENAMES" => files.keys.join(":") }
          )
          Dir.glob("**/*", File::FNM_DOTMATCH)
             .select { |path| File.file?(path) && !files.key?(path) }
             .to_h { |path| [path, File.read(path)] }
        end
      end
    end

    def requirement(file, version)
      { requirement: version, file: file, groups: [], source: nil }
    end

    def locked(content, tool)
      TomlRB.parse(content).dig("tools", tool)
    end

    context "with mise.lock next to mise.toml" do
      it "updates the tool in both files" do
        expect(updated_files.keys).to eq(%w(mise.toml mise.lock))
        expect(locked(updated_files["mise.lock"], "node").map { |entry| entry["version"] }).to eq(["20.1.0"])
      end

      it "leaves other tools and the locked platforms unchanged" do
        expect(locked(updated_files["mise.lock"], "terraform")).to eq(locked(lockfiles["mise.lock"], "terraform"))
        expect(updated_files["mise.lock"].scan(/"platforms\.([^"]+)"/).flatten.uniq).to eq(["linux-x64"])
      end
    end

    context "when the update checker selects the version" do
      let(:ignored_versions) { [] }
      let(:parsed) { Dependabot::Mise::FileParser.new(dependency_files: dependency_files, source: nil).parse.fetch(0) }
      let(:checker) do
        Dependabot::Mise::UpdateChecker.new(
          dependency: parsed,
          dependency_files: dependency_files,
          credentials: [],
          ignored_versions: ignored_versions,
          raise_on_ignored: false
        )
      end
      let(:dependency) { checker.updated_dependencies(requirements_to_unlock: :own).fetch(0) }
      let(:locked_node) { locked(updated_files["mise.lock"], "node").fetch(0) }

      context "with a loose pin" do
        let(:manifests) { { "mise.toml" => "[tools]\nnode = '20'\n" } }

        it "keeps the pin loose and locks the selected version" do
          expect(updated_files["mise.toml"]).to eq("[tools]\nnode = '#{dependency.version.split('.').first}'\n")
          expect(locked_node["version"]).to eq(dependency.version)
        end

        context "when an ignore rule holds back newer releases matching the new pin" do
          let(:ignored_versions) { ["> 22.0.0"] }

          it "pins and locks the selected version exactly" do
            expect(dependency.version).to eq("22.0.0")
            expect(updated_files["mise.toml"]).to eq("[tools]\nnode = '22.0.0'\n")
            expect(locked_node["version"]).to eq("22.0.0")
          end
        end
      end

      context "with a latest pin" do
        let(:manifests) { { "mise.toml" => "[tools]\nnode = 'latest'\n" } }
        let(:lockfiles) do
          lock("mise.toml" => "[tools]\nnode = '20.0.0'\n")
            .transform_values { |content| content.sub('specifiers = ["20.0.0"]', 'specifiers = ["latest"]') }
        end

        it "updates only the lockfile, to the selected version" do
          expect(parsed.version).to eq("20.0.0")
          expect(updated_files.keys).to eq(["mise.lock"])
          expect([locked_node["version"], locked_node["specifiers"]]).to eq([dependency.version, ["latest"]])
        end

        context "when an ignore rule excludes the version mise resolves it to" do
          let(:ignored_versions) { ["> 22.0.0"] }

          it "proposes no update" do
            expect(checker.can_update?(requirements_to_unlock: :own)).to be(false)
          end
        end
      end
    end

    context "with an environment lockfile" do
      let(:manifests) do
        { "mise.toml" => "[tools]\nnode = '20.0.0'\n", "mise.dev.toml" => "[tools]\nnode = '20.0.0'\n" }
      end
      let(:updates) { { "mise.toml" => %w(20.0.0 20.0.0), "mise.dev.toml" => %w(20.0.0 20.1.0) } }

      it "updates only the lockfile of the changed manifest" do
        expect(lockfiles.keys).to contain_exactly("mise.lock", "mise.dev.lock")
        expect(updated_files.keys).to eq(%w(mise.dev.toml mise.dev.lock))
        expect(locked(updated_files["mise.dev.lock"], "node").map { |entry| entry["version"] }).to eq(["20.1.0"])
      end
    end

    context "with conf.d fragments sharing a lockfile" do
      let(:manifests) do
        {
          "mise/conf.d/node.toml" => "[tools]\nnode = '20.0.0'\n",
          "mise/conf.d/legacy.toml" => "[tools]\nnode = '18.0.0'\n"
        }
      end
      let(:updates) { { "mise/conf.d/node.toml" => %w(20.0.0 20.1.0), "mise/conf.d/legacy.toml" => %w(18.0.0 18.0.0) } }

      it "keeps the versions the other manifests pin" do
        expect(lockfiles.keys).to eq(["mise/mise.lock"])
        expect(updated_files.keys).to eq(%w(mise/conf.d/node.toml mise/mise.lock))
        expect(locked(updated_files["mise/mise.lock"], "node").map { |entry| entry["version"] })
          .to contain_exactly("18.0.0", "20.1.0")
      end
    end

    context "with a conf.d folder and a config file sharing a lockfile" do
      let(:manifests) do
        {
          "mise/config.toml" => "[tools]\nterraform = '1.9.0'\n",
          "mise/conf.d/node/mise.toml" => "[tools]\nnode = '20.0.0'\n"
        }
      end
      let(:updates) { { "mise/conf.d/node/mise.toml" => %w(20.0.0 20.1.0) } }

      it "updates the shared lockfile" do
        expect(lockfiles.keys).to eq(["mise/mise.lock"])
        expect(updated_files.keys).to eq(%w(mise/conf.d/node/mise.toml mise/mise.lock))
        expect(locked(updated_files["mise/mise.lock"], "node").map { |entry| entry["version"] }).to eq(["20.1.0"])
        expect(locked(updated_files["mise/mise.lock"], "terraform"))
          .to eq(locked(lockfiles["mise/mise.lock"], "terraform"))
      end
    end

    context "without a lockfile" do
      let(:lockfiles) { {} }

      it "updates the manifest without running mise lock" do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original

        expect(updated_files.keys).to eq(["mise.toml"])
        expect(Dependabot::SharedHelpers).not_to have_received(:run_shell_command)
      end
    end

    {
      "mise.toml" => %w(mise.lock .mise/locks),
      ".mise/config.toml" => %w(.mise/mise.lock .mise/locks),
      ".config/mise.toml" => %w(.config/mise.lock .config/mise/locks)
    }.each do |manifest, (lockfile, sidecar_root)|
      context "with a backend that writes sidecar files, configured in #{manifest}" do
        let(:manifests) { { manifest => "[tools]\n\"npm:prettier\" = '3.3.0'\n" } }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "npm:prettier",
            version: "3.3.3",
            previous_version: "3.3.0",
            package_manager: "mise",
            requirements: [requirement(manifest, "3.3.3")],
            previous_requirements: [requirement(manifest, "3.3.0")]
          )
        end
        let(:sidecar_files) do
          lambda do |version|
            sidecar_names.map { |name| "#{sidecar_root}/npm-prettier/#{version}/#{name}" }
          end
        end

        it "replaces the old version's sidecar files with the new ones" do
          expect(lockfiles.keys).to contain_exactly(lockfile, *sidecar_files.call("3.3.0"))
          expect(changes.map { |file| [file.name, file.operation] }).to contain_exactly(
            [manifest, "update"],
            [lockfile, "update"],
            *sidecar_files.call("3.3.3").map { |name| [name, "create"] },
            *sidecar_files.call("3.3.0").map { |name| [name, "delete"] }
          )
        end
      end
    end

    context "with two lockfiles sharing a sidecar directory" do
      let(:tool) { "npm:prettier" }
      let(:manifests) do
        {
          "mise.toml" => "[tools]\n\"npm:prettier\" = '3.3.0'\n",
          ".mise/config.toml" => "[tools]\n\"npm:prettier\" = '3.3.0'\n"
        }
      end
      let(:old_sidecar) { sidecar_names.map { |name| ".mise/locks/npm-prettier/3.3.0/#{name}" } }
      let(:new_sidecar) { sidecar_names.map { |name| ".mise/locks/npm-prettier/3.3.3/#{name}" } }

      context "when only one manifest is updated" do
        let(:updates) { { "mise.toml" => %w(3.3.0 3.3.3), ".mise/config.toml" => %w(3.3.0 3.3.0) } }

        it "keeps the sidecar files the other lockfile still uses" do
          expect(lockfiles.keys).to contain_exactly("mise.lock", ".mise/mise.lock", *old_sidecar)
          expect(changes.map { |file| [file.name, file.operation] }).to contain_exactly(
            ["mise.toml", "update"],
            ["mise.lock", "update"],
            *new_sidecar.map { |name| [name, "create"] }
          )
        end
      end

      context "when both manifests are updated" do
        let(:updates) { { "mise.toml" => %w(3.3.0 3.3.3), ".mise/config.toml" => %w(3.3.0 3.3.3) } }

        it "creates and deletes each sidecar file once" do
          expect(changes.map { |file| [file.name, file.operation] }).to contain_exactly(
            ["mise.toml", "update"],
            [".mise/config.toml", "update"],
            ["mise.lock", "update"],
            [".mise/mise.lock", "update"],
            *new_sidecar.map { |name| [name, "create"] },
            *old_sidecar.map { |name| [name, "delete"] }
          )
        end
      end
    end

    context "when mise lock changes files it doesn't manage" do
      let(:lockfiles) { { "mise.lock" => "lockfile_version = 4\n" } }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(["mise", "lock", "--", "node"], hash_including(stderr_to_stdout: false)) do
          File.write("mise.lock", "lockfile_version = 4\n# updated\n")
          File.write("unexpected.txt", "x")
          ""
        end
      end

      it "fails rather than leave the lockfile out of step with the manifest" do
        expect { changes }.to raise_error(Dependabot::DependencyFileNotResolvable, /unexpected\.txt/)
      end
    end

    context "when mise locks a different version than the one selected" do
      let(:lockfiles) { { "mise.lock" => "lockfile_version = 4\n" } }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(["mise", "lock", "--", "node"], hash_including(stderr_to_stdout: false)) do
          File.write("mise.lock", "lockfile_version = 4\n# updated\n")
          ""
        end
        allow(Dependabot::SharedHelpers).to mise_ls("node").and_return(JSON.dump([{ "version" => "20.0.9" }]))
      end

      it "fails rather than report the wrong version" do
        expect { changes }
          .to raise_error(Dependabot::DependencyFileNotResolvable, /node in mise.toml to 20.0.9, not 20.1.0/)
      end
    end

    context "when mise lock fails" do
      let(:lockfiles) { { "mise.lock" => "lockfile_version = 4\n" } }

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .with(["mise", "lock", "--", "node"], hash_including(stderr_to_stdout: false))
          .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: "network down", error_context: {}))
      end

      it "reports the lockfile as unresolvable" do
        expect { updated_files }.to raise_error(Dependabot::DependencyFileNotResolvable, "network down")
      end
    end
  end
end
