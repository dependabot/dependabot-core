# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/update_checker/subdependency_version_resolver"
require "dependabot/npm_and_yarn/file_updater/yarn_lockfile_updater"

# Sorbet fixture signatures must stay beside their lets and use concrete types.
# rubocop:disable-next RSpec/ScatteredLet, RSpec/DescribedClass
RSpec.describe Dependabot::NpmAndYarn::UpdateChecker::SubdependencyVersionResolver do
  extend T::Sig

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let(:dependency_files) { project_dependency_files("yarn_berry/multiple_brace_expansion_versions") }
  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "brace-expansion",
      version: "2.1.2",
      requirements: [],
      package_manager: "npm_and_yarn"
    )
  end
  sig { returns(Dependabot::NpmAndYarn::UpdateChecker::SubdependencyVersionResolver) }
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: [],
      ignored_versions: [],
      latest_allowable_version: "5.0.12",
      target_version: "2.1.4",
      repo_contents_path: nil
    )
  end

  sig { returns(String) }
  let(:updated_version) { "2.1.4" }

  sig { returns(String) }
  let(:updated_lockfile_content) do
    lockfile = T.must(dependency_files.find { |file| file.name == "yarn.lock" })
    T.must(lockfile.content).gsub("2.1.2", updated_version)
  end

  before do
    allow(Dependabot::Experiments).to receive(:enabled?).and_return(false)
    allow(Dependabot::NpmAndYarn::Helpers).to receive_messages(
      yarn_major_version: 4,
      yarn_berry_supports_minimal_age_gate?: true
    )
    allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_yarn_command) do
      lockfile = T.must(dependency_files.find { |file| file.name == "yarn.lock" })
      manifest = JSON.parse(File.read("package.json"))
      content = if manifest.fetch("resolutions", {})["brace-expansion@npm:^2.0.2"] == "npm:2.1.4"
                  T.must(lockfile.content).gsub("2.1.2", "2.1.4")
                else
                  updated_lockfile_content
                end
      File.write("yarn.lock", content)
      ""
    end
  end

  it "reports the updated resolution rather than the unrelated lowest installed version" do
    expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
    expect(Dependabot::NpmAndYarn::Helpers).to have_received(:run_yarn_command).with(
      "install --mode=update-lockfile",
      fingerprint: "install",
      env: { "YARN_NPM_MINIMAL_AGE_GATE" => "0" }
    ).twice
  end

  context "with Yarn 2" do
    before do
      allow(Dependabot::NpmAndYarn::Helpers).to receive_messages(
        yarn_major_version: 2,
        yarn_berry_supports_minimal_age_gate?: false
      )
    end

    it "uses supported arguments for both resolution installs" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
      expect(Dependabot::NpmAndYarn::Helpers).to have_received(:run_yarn_command)
        .with("install", fingerprint: "install", env: nil).twice
    end
  end

  context "with an unrelated pinned version above the current version" do
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) do
      files = T.let(super(), T::Array[Dependabot::DependencyFile])
      files.map do |file|
        next file unless file.name == "yarn.lock"

        lockfile = file.dup
        lockfile.content = T.must(file.content)
                            .gsub("^1.1.7", "2.1.3")
                            .gsub("1.1.12", "2.1.3")
        lockfile
      end
    end

    it "reports the targeted resolution rather than the unrelated pinned version" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
    end
  end

  context "when the targeted resolution cannot be updated" do
    sig { returns(String) }
    let(:updated_version) { "2.1.2" }

    it "reports the unchanged targeted version" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.2"))
    end
  end

  context "when Yarn removes the original descriptor" do
    sig { returns(String) }
    let(:updated_lockfile_content) { super().gsub("^2.0.2", "^2.0.3") }

    it "does not report an unrelated resolution as a successful update" do
      allow(Dependabot.logger).to receive(:info)
      expect(Dependabot.logger).to receive(:info)
        .with("Cannot verify updated Yarn resolution for brace-expansion@npm:^2.0.2; keeping current version")

      expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.2"))
    end
  end

  it "uses the resolved version when generating the lockfile and retains separate major versions" do
    updated_dependency = Dependabot::Dependency.new(
      name: dependency.name,
      version: T.must(resolver.latest_resolvable_version).to_s,
      previous_version: dependency.version,
      requirements: [],
      previous_requirements: [],
      package_manager: dependency.package_manager
    )
    content = Dependabot::NpmAndYarn::FileUpdater::YarnLockfileUpdater.new(
      dependencies: [updated_dependency],
      dependency_files: dependency_files,
      credentials: [],
      repo_contents_path: nil,
      security_updates_only: true
    ).updated_yarn_lock_content(T.must(dependency_files.find { |file| file.name == "yarn.lock" }))

    expect(content).to include(
      'resolution: "brace-expansion@npm:2.1.4"',
      'resolution: "brace-expansion@npm:1.1.12"',
      'resolution: "brace-expansion@npm:5.0.2"'
    )
    expect(content).not_to include('resolution: "brace-expansion@npm:2.1.2"')
    expect(Dependabot::NpmAndYarn::Helpers).to have_received(:run_yarn_command).with(
      "install #{Dependabot::NpmAndYarn::Helpers.yarn_berry_args}".strip,
      fingerprint: "install",
      env: { "YARN_NPM_MINIMAL_AGE_GATE" => "0" }
    ).at_least(:once)
  end

  it "rejects a fixed version outside the exact installed descriptor's requirement" do
    lockfile = T.must(dependency_files.find { |file| file.name == "yarn.lock" }).dup
    lockfile.content = T.must(lockfile.content).gsub("^2.0.2", "2.1.2")
    expect(Dependabot::NpmAndYarn::Helpers).not_to receive(:run_yarn_command)

    expect do
      Dependabot::NpmAndYarn::FileUpdater::BerryLockfileHandler.update_subdependency(
        yarn_lock: lockfile,
        dependency: dependency,
        target_version: "2.1.4"
      )
    end.to raise_error(Dependabot::DependencyFileNotResolvable, /incompatible requirement/)
  end

  it "restores the original manifest when the temporary resolution install fails" do
    error = Dependabot::SharedHelpers::HelperSubprocessFailed.new(
      message: "fixture install failed", error_context: {}
    )
    allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_yarn_command).and_raise(error)
    files = dependency_files

    Dependabot::SharedHelpers.in_a_temporary_directory do
      files.each { |file| File.write(file.name, T.must(file.content)) }
      original_manifest = File.read("package.json")

      expect do
        Dependabot::NpmAndYarn::FileUpdater::BerryLockfileHandler.update_subdependency(
          yarn_lock: T.must(dependency_files.find { |file| file.name == "yarn.lock" }),
          dependency: dependency,
          target_version: "2.1.4"
        )
      end.to raise_error(Dependabot::SharedHelpers::HelperSubprocessFailed, "fixture install failed")

      expect(File.read("package.json")).to eq(original_manifest)
    end
  end

  it "resolves the security fix through the update checker's public entry point" do
    versions = %w(1.1.12 1.1.18 2.1.2 2.1.4 5.0.2 5.0.12)
    registry_response = {
      "name" => dependency.name,
      "dist-tags" => { "latest" => "5.0.12" },
      "versions" => versions.to_h do |version|
        [
          version,
          {
            "name" => dependency.name,
            "version" => version,
            "dist" => { "tarball" => "https://registry.npmjs.org/brace-expansion/-/brace-expansion-#{version}.tgz" }
          }
        ]
      end
    }
    stub_request(:get, "https://registry.npmjs.org/brace-expansion")
      .to_return(status: 200, body: registry_response.to_json, headers: { "Content-Type" => "application/json" })
    stub_request(:head, %r{\Ahttps://registry\.npmjs\.org/brace-expansion/-/brace-expansion-[\d.]+\.tgz\z})
      .to_return(status: 200)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_yarn_berry_conflicting_dependencies).and_return(true)
    checker = Dependabot::NpmAndYarn::UpdateChecker.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: [],
      security_advisories: [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency.name,
          package_manager: dependency.package_manager,
          vulnerable_versions: Dependabot::NpmAndYarn::Requirement.requirements_array(">= 2.0.0 < 2.1.4")
        )
      ]
    )

    expect(checker.can_update?(requirements_to_unlock: :own)).to be(true)
    expect(checker.lowest_resolvable_security_fix_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
    expect(checker.updated_dependencies(requirements_to_unlock: :own).map(&:version)).to eq(["2.1.4"])
  end
end
