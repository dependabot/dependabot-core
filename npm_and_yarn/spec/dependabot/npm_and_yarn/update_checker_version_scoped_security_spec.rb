# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "securerandom"
require "dependabot/npm_and_yarn/update_checker"
require "dependabot/npm_and_yarn/file_updater/yarn_lockfile_updater"
require_relative "../../support/npm_registry"

# Sorbet fixture signatures must stay beside their lets and use concrete types.
# rubocop:disable-next RSpec/ScatteredLet, RSpec/DescribedClass
RSpec.describe(Dependabot::NpmAndYarn::UpdateChecker) do
  extend T::Sig

  sig { returns(String) }
  let(:dependency_name) { "brace-expansion" }

  sig { returns(String) }
  let(:installed_requirement) { "^1.1.17" }

  sig { returns(T::Array[String]) }
  let(:ignored_versions) { [] }

  sig { returns(T::Hash[String, T::Boolean]) }
  let(:in_range_release_details) { {} }

  sig { returns(T::Array[String]) }
  let(:releases) { %w(1.1.18 1.1.21 2.1.7 5.0.12) }

  sig { returns(T::Hash[String, String]) }
  let(:dist_tags) { { "latest" => "5.0.12", "maintenance" => "1.1.21", "_maintenance" => "1.1.21" } }

  sig { returns(String) }
  let(:registry_url) { "https://registry.npmjs.org" }

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let(:dependency_files) do
    project_dependency_files("yarn_berry/version_scoped_security").map do |file|
      content = T.must(file.content).gsub("brace-expansion", dependency_name)
                 .gsub("^1.1.17", installed_requirement)
                 .gsub("    #{dependency_name}:", "    #{JSON.generate(dependency_name)}:")
      Dependabot::DependencyFile.new(name: file.name, content: content, directory: file.directory)
    end
  end

  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name, version: "1.1.18", requirements: [], package_manager: "npm_and_yarn"
    )
  end

  sig { returns(Dependabot::NpmAndYarn::UpdateChecker) }
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: [],
      ignored_versions: ignored_versions,
      raise_on_ignored: true,
      security_advisories: [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "npm_and_yarn",
          vulnerable_versions: [">= 1.1.18 < 1.1.21", ">= 1.2.0 < 2.1.7", ">= 5.0.0 < 5.0.12"].flat_map do |requirement|
            Dependabot::NpmAndYarn::Requirement.requirements_array(requirement)
          end
        )
      ]
    )
  end

  before do
    stub_request(:get, "#{registry_url}/#{dependency_name.gsub('/', '%2F')}").to_return(
      status: 200,
      body: JSON.generate(
        "name" => dependency_name,
        "dist-tags" => dist_tags,
        "versions" => releases.to_h do |version|
          details = { "name" => dependency_name, "version" => version }
          [version, version == "1.1.21" ? details.merge(in_range_release_details) : details]
        end
      )
    )
    stub_request(:head, %r{\A#{Regexp.escape(registry_url)}/#{Regexp.escape(dependency_name)}/-/[^/]+\.tgz\z})
      .to_return(status: 200)
    stub_request(:get, %r{\A#{Regexp.escape(registry_url)}/#{Regexp.escape(dependency_name)}/\d[^/]*\z})
      .to_return(status: 200, body: "{}")
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_yarn_berry_conflicting_dependencies).and_return(true)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_audit_fix_fallback).and_return(false)
  end

  it "selects the latest release in the range resolving to the vulnerable installation" do
    expect(checker.latest_version.to_s).to eq("1.1.21")
  end

  it "does not treat other installed versions' ranges as conflicts" do
    expect(checker.conflicting_dependencies).to be_empty
  end

  it "finds the in-range security fix" do
    expect(checker.lowest_security_fix_version.to_s).to eq("1.1.21")
  end

  it "allows the in-range security update to resolve" do
    allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_yarn_command) do
      lockfile = YAML.safe_load_file("yarn.lock")
      record = lockfile.fetch("brace-expansion@npm:^1.1.17")
      record["version"] = "1.1.21"
      record["resolution"] = "brace-expansion@npm:1.1.21"
      File.write("yarn.lock", YAML.dump(lockfile))
      ""
    end

    expect(checker.lowest_resolvable_security_fix_version.to_s).to eq("1.1.21")
  end

  it "retains conflicts from requirements resolving to the targeted installation" do
    conflicts = Dependabot::NpmAndYarn::UpdateChecker::ConflictingDependencyResolver.new(
      dependency_files: dependency_files, credentials: []
    ).conflicting_dependencies(dependency: dependency, target_version: "2.1.7")

    expect(conflicts.map { |conflict| conflict.fetch("requirement") }).to eq(["^1.1.17"])
  end

  context "when a higher in-range release is vulnerable" do
    sig { returns(T::Array[String]) }
    let(:releases) { %w(1.1.18 1.1.21 1.2.0 2.1.7 5.0.12) }

    sig { returns(T::Hash[String, String]) }
    let(:package_scripts) { {} }

    sig { returns(T::Hash[String, T::Array[NpmRegistry::Manifest]]) }
    let(:registry_overrides) { {} }

    sig { returns(NpmRegistry) }
    let(:registry) do
      versions = releases + %w(2.1.2 5.0.2)
      packages = {
        dependency_name => versions.map do |version|
          { "name" => dependency_name, "version" => version, "scripts" => package_scripts }
        end
      }
      { "legacy-parent" => "^1.1.17", "current-parent" => "^2.0.2", "modern-parent" => "^5.0.2" }.each do |name, range|
        packages[name] = [{ "name" => name, "version" => "1.0.0", "dependencies" => { dependency_name => range } }]
      end
      NpmRegistry.new(packages: packages.merge(registry_overrides))
    end

    sig { returns(String) }
    let(:registry_url) { registry.url.sub("http:", "https:") }

    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) do
      T.cast(super(), T::Array[Dependabot::DependencyFile]) + [
        Dependabot::DependencyFile.new(
          name: ".yarnrc.yml",
          content: YAML.dump(
            "npmRegistryServer" => registry.url,
            "unsafeHttpWhitelist" => ["127.0.0.1"],
            "enableGlobalCache" => false,
            "enableScripts" => false
          )
        )
      ]
    end

    after { registry.close }

    sig { returns(String) }
    let(:updated_yarn_lock) do
      updated_dependency = Dependabot::Dependency.new(
        name: dependency_name,
        version: "1.1.21",
        previous_version: "1.1.18",
        requirements: [],
        previous_requirements: [],
        package_manager: "npm_and_yarn"
      )
      updater = Dependabot::NpmAndYarn::FileUpdater.new(
        dependencies: [updated_dependency],
        dependency_files: dependency_files,
        credentials: [],
        options: { security_updates_only: true }
      )
      T.must(T.must(updater.updated_dependency_files.find { |file| file.name == "yarn.lock" }).content)
    end

    it "selects and resolves the secure backport using real Yarn" do
      expect(checker.latest_version.to_s).to eq("1.1.21")
      expect(checker.lowest_security_fix_version.to_s).to eq("1.1.21")
      expect(checker.lowest_resolvable_security_fix_version.to_s).to eq("1.1.21")
    end

    it "writes the selected secure version without changing other installed versions" do
      parsed = YAML.safe_load(updated_yarn_lock)

      expect(parsed.fetch("brace-expansion@npm:^1.1.17").fetch("version")).to eq("1.1.21")
      expect(parsed.fetch("brace-expansion@npm:^2.0.2").fetch("version")).to eq("2.1.2")
      expect(parsed.fetch("brace-expansion@npm:^5.0.2").fetch("version")).to eq("5.0.2")
    end

    context "with an unrelated lower installation" do
      sig { returns(T::Array[String]) }
      let(:releases) { %w(1.0.0 1.1.18 1.1.21 1.2.0 2.1.7 5.0.12) }

      sig { returns(T::Hash[String, T::Array[NpmRegistry::Manifest]]) }
      let(:registry_overrides) do
        { "earlier-parent" => [{ "name" => "earlier-parent", "version" => "1.0.0",
                                 "dependencies" => { dependency_name => "1.0.0" } }] }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) do
        T.cast(super(), T::Array[Dependabot::DependencyFile]).map do |file|
          content = T.must(file.content)
          if file.name == "package.json"
            manifest = JSON.parse(content)
            manifest.fetch("dependencies")["earlier-parent"] = "1.0.0"
            content = JSON.generate(manifest)
          elsif file.name == "yarn.lock"
            parsed = YAML.safe_load(content)
            parsed["earlier-parent@npm:1.0.0"] = {
              "version" => "1.0.0", "resolution" => "earlier-parent@npm:1.0.0",
              "languageName" => "node", "linkType" => "hard", "dependencies" => { dependency_name => "npm:1.0.0" }
            }
            parsed["#{dependency_name}@npm:1.0.0"] = {
              "version" => "1.0.0", "resolution" => "#{dependency_name}@npm:1.0.0",
              "languageName" => "node", "linkType" => "hard"
            }
            content = YAML.dump(parsed)
          end
          Dependabot::DependencyFile.new(name: file.name, content: content, directory: file.directory)
        end
      end

      it "reports the targeted version rather than the unrelated lower version" do
        expect(checker.lowest_resolvable_security_fix_version.to_s).to eq("1.1.21")
      end
    end

    context "when the installation is aliased" do
      sig { returns(T::Hash[String, T::Array[NpmRegistry::Manifest]]) }
      let(:registry_overrides) do
        { "legacy-parent" => [{ "name" => "legacy-parent", "version" => "1.0.0",
                                "dependencies" => { "legacy-brace" => "npm:#{dependency_name}@^1.1.17" } }] }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) do
        T.cast(super(), T::Array[Dependabot::DependencyFile]).map do |file|
          next file unless file.name == "yarn.lock"

          content = T.must(file.content)
                     .sub("\"#{dependency_name}@npm:^1.1.17\"",
                          "\"legacy-brace@npm:#{dependency_name}@^1.1.17\"")
                     .sub("#{JSON.generate(dependency_name)}: \"npm:^1.1.17\"",
                          "legacy-brace: \"npm:#{dependency_name}@^1.1.17\"")
          Dependabot::DependencyFile.new(name: file.name, content: content, directory: file.directory)
        end
      end

      it "resolves an unscoped alias using real Yarn" do
        expect(checker.lowest_resolvable_security_fix_version.to_s).to eq("1.1.21")
        expect(
          YAML.safe_load(updated_yarn_lock).fetch("legacy-brace@npm:#{dependency_name}@^1.1.17")
                    .fetch("version")
        ).to eq("1.1.21")
      end

      context "with a scoped package name" do
        sig { returns(String) }
        let(:dependency_name) { "@scope/brace-expansion" }

        it "resolves a scoped alias using real Yarn" do
          expect(checker.lowest_resolvable_security_fix_version.to_s).to eq("1.1.21")
          expect(
            YAML.safe_load(updated_yarn_lock).fetch("legacy-brace@npm:#{dependency_name}@^1.1.17")
                        .fetch("version")
          ).to eq("1.1.21")
        end
      end
    end

    context "when Yarn 3 explicitly enables a dependency build" do
      sig { returns(String) }
      let(:script_marker) { File.join(Dir.tmpdir, "dependabot-build-#{SecureRandom.hex}") }

      sig { returns(T::Hash[String, String]) }
      let(:package_scripts) do
        { "postinstall" => "node -e 'require(\"fs\").writeFileSync(#{script_marker.to_json}, \"built\")'" }
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) do
        T.cast(super(), T::Array[Dependabot::DependencyFile]).map do |file|
          content = T.must(file.content)
          if file.name == "package.json"
            manifest = JSON.parse(content)
            manifest["dependenciesMeta"] = { dependency_name => { "built" => true } }
            content = JSON.generate(manifest)
          elsif file.name == ".yarnrc.yml"
            settings = YAML.safe_load(content)
            settings["yarnPath"] = File.expand_path(
              "../../fixtures/projects/yarn_berry/simple_node_modules/.yarn/releases/yarn-3.3.0.cjs", __dir__
            )
            content = YAML.dump(settings)
          end
          Dependabot::DependencyFile.new(name: file.name, content: content, directory: file.directory)
        end
      end

      after { FileUtils.rm_f(script_marker) }

      it "resolves without executing the explicitly enabled build" do
        expect(checker.lowest_resolvable_security_fix_version.to_s).to eq("1.1.21")
        expect(File).not_to exist(script_marker)
      end

      it "updates the lockfile without executing the explicitly enabled build" do
        expect(YAML.safe_load(updated_yarn_lock).fetch("brace-expansion@npm:^1.1.17").fetch("version"))
          .to eq("1.1.21")
        expect(File).not_to exist(script_marker)
      end
    end
  end

  context "when the vulnerable installation is pinned" do
    sig { returns(String) }
    let(:installed_requirement) { "1.1.18" }

    it "retains a secure target for reporting the blocking parent" do
      expect(checker.up_to_date?).to be(false)
      expect(checker.lowest_security_fix_version.to_s).to eq("1.1.21")
      expect(checker.conflicting_dependencies.map { |conflict| conflict.fetch("requirement") }).to eq(["1.1.18"])
    end

    it "does not override the pin when normalized conflict checking is disabled" do
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:enable_yarn_berry_conflicting_dependencies).and_return(false)
      expect(Dependabot::NpmAndYarn::Helpers).not_to receive(:run_yarn_command)

      expect(checker.lowest_resolvable_security_fix_version).to be_nil
    end
  end

  context "when the only in-range security fix is deprecated" do
    sig { returns(T::Hash[String, T::Boolean]) }
    let(:in_range_release_details) { { "deprecated" => true } }

    it "retains an eligible security target for blocker diagnostics" do
      expect(checker.up_to_date?).to be(false)
      expect(checker.lowest_security_fix_version.to_s).to eq("2.1.7")
      expect(checker.conflicting_dependencies.map { |conflict| conflict.fetch("requirement") }).to eq(["^1.1.17"])
    end
  end

  context "when the only in-range security fix is ignored" do
    sig { returns(T::Array[String]) }
    let(:ignored_versions) { ["1.1.21"] }

    it "retains an eligible security target for blocker diagnostics" do
      expect(checker.up_to_date?).to be(false)
      expect(checker.lowest_security_fix_version.to_s).to eq("2.1.7")
      expect(checker.conflicting_dependencies.map { |conflict| conflict.fetch("requirement") }).to eq(["^1.1.17"])
    end
  end

  context "when the only in-range security fix is yanked" do
    before do
      stub_request(:head, "https://registry.npmjs.org/brace-expansion/-/brace-expansion-1.1.21.tgz")
        .to_return(status: 404)
    end

    it "retains an eligible security target for blocker diagnostics" do
      expect(checker.up_to_date?).to be(false)
      expect(checker.lowest_security_fix_version.to_s).to eq("2.1.7")
      expect(checker.conflicting_dependencies.map { |conflict| conflict.fetch("requirement") }).to eq(["^1.1.17"])
    end
  end

  context "when all security fixes are ignored" do
    sig { returns(T::Array[String]) }
    let(:ignored_versions) { %w(1.1.21 2.1.7 5.0.12) }

    it "raises after filtering all security fix candidates" do
      expect { checker.lowest_security_fix_version }.to raise_error(Dependabot::AllVersionsIgnored)
    end
  end

  context "when the vulnerable installation is only referenced through an npm alias" do
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) do
      T.cast(super(), T::Array[Dependabot::DependencyFile]).map do |file|
        next file unless file.name == "yarn.lock"

        content = T.must(file.content)
                   .sub("\"#{dependency_name}@npm:^1.1.17\"",
                        "\"legacy-brace@npm:#{dependency_name}@^1.1.17\"")
                   .sub("#{JSON.generate(dependency_name)}: \"npm:^1.1.17\"",
                        "legacy-brace: \"npm:#{dependency_name}@^1.1.17\"")
        Dependabot::DependencyFile.new(name: file.name, content: content, directory: file.directory)
      end
    end

    it "selects the in-range security update" do
      expect(checker.latest_version.to_s).to eq("1.1.21")
      expect(checker.lowest_security_fix_version.to_s).to eq("1.1.21")
      expect(checker.conflicting_dependencies).to be_empty
    end

    context "with a scoped real package name" do
      sig { returns(String) }
      let(:dependency_name) { "@scope/brace-expansion" }

      it "selects the in-range security update" do
        expect(checker.latest_version.to_s).to eq("1.1.21")
        expect(checker.lowest_security_fix_version.to_s).to eq("1.1.21")
        expect(checker.conflicting_dependencies).to be_empty
      end
    end
  end

  context "when a grouped descriptor includes a removed standard dist-tag" do
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) do
      T.cast(super(), T::Array[Dependabot::DependencyFile]).map do |file|
        next file unless file.name == "yarn.lock"

        content = T.must(file.content).sub(
          "brace-expansion@npm:^1.1.17", "brace-expansion@npm:^1.1.17, brace-expansion@npm:next"
        )
        Dependabot::DependencyFile.new(name: file.name, content: content, directory: file.directory)
      end
    end

    it "keeps the semver range while skipping the missing tag" do
      expect(checker.latest_version.to_s).to eq("1.1.21")
      expect(checker.lowest_security_fix_version.to_s).to eq("1.1.21")
    end
  end

  context "when the lockfile descriptor uses a standard dist-tag" do
    sig { returns(String) }
    let(:installed_requirement) { "latest" }

    it "does not filter numeric security fixes using the tag as a semver range" do
      expect(checker.latest_version.to_s).to eq("5.0.12")
      expect(checker.lowest_security_fix_version.to_s).to eq("1.1.21")
    end
  end

  context "when the lockfile descriptor uses a custom dist-tag" do
    sig { returns(String) }
    let(:installed_requirement) { "maintenance" }

    it "does not raise or discard numeric security fixes" do
      expect(checker.latest_version.to_s).to eq("5.0.12")
      expect(checker.lowest_security_fix_version.to_s).to eq("1.1.21")
    end
  end

  context "when the lockfile descriptor uses an underscore-prefixed dist-tag" do
    sig { returns(String) }
    let(:installed_requirement) { "_maintenance" }

    it "recognizes the registry tag without parsing it as a semver range" do
      expect(checker.latest_version.to_s).to eq("5.0.12")
      expect(checker.lowest_security_fix_version.to_s).to eq("1.1.21")
    end

    context "when the tag has been removed from the registry" do
      sig { returns(T::Hash[String, String]) }
      let(:dist_tags) { { "latest" => "5.0.12" } }

      it "skips the unparseable selector and retains numeric security fixes" do
        expect(checker.latest_version.to_s).to eq("5.0.12")
        expect(checker.lowest_security_fix_version.to_s).to eq("1.1.21")
      end
    end
  end
end
