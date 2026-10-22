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
      target_version: target_version,
      repo_contents_path: nil
    )
  end

  sig { returns(String) }
  let(:updated_version) { "2.1.4" }

  sig { returns(T.nilable(String)) }
  let(:target_version) { "2.1.4" }

  sig { returns(String) }
  let(:updated_lockfile_content) do
    lockfile = T.must(dependency_files.find { |file| file.name == "yarn.lock" })
    T.must(lockfile.content).gsub("2.1.2", updated_version)
  end

  before do
    allow(Dependabot::Experiments).to receive(:enabled?).and_return(false)
    allow(Dependabot::Experiments).to receive(:enabled?)
      .with(:enable_yarn_berry_conflicting_dependencies).and_return(true)
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

  context "when the experiment is disabled" do
    before do
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:enable_yarn_berry_conflicting_dependencies).and_return(false)
    end

    it "uses the unscoped Yarn update and combined installed version" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("1.1.12"))
      expect(Dependabot::NpmAndYarn::Helpers).to have_received(:run_yarn_command).with(
        "up -R brace-expansion --mode=update-lockfile",
        fingerprint: "up -R <dependency_name> --mode=update-lockfile"
      ).once
    end

    it "generates security updates using the legacy add, dedupe, and remove commands" do
      allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_yarn_commands) do
        File.write("yarn.lock", updated_lockfile_content)
        ""
      end
      updated_dependency = Dependabot::Dependency.new(
        name: dependency.name,
        version: "2.1.4",
        previous_version: dependency.version,
        requirements: [],
        previous_requirements: [],
        package_manager: dependency.package_manager
      )
      updater = Dependabot::NpmAndYarn::FileUpdater::YarnLockfileUpdater.new(
        dependencies: [updated_dependency],
        dependency_files: dependency_files,
        credentials: [],
        repo_contents_path: nil,
        security_updates_only: true
      )
      lockfile = T.must(dependency_files.find { |file| file.name == "yarn.lock" })

      expect(updater.updated_yarn_lock_content(lockfile)).to include("brace-expansion@npm:2.1.4")
      expect(Dependabot::NpmAndYarn::Helpers).not_to have_received(:run_yarn_command)
      expect(Dependabot::NpmAndYarn::Helpers).to have_received(:run_yarn_commands).with(
        ["add brace-expansion@2.1.4 --mode=update-lockfile", "add <update> --mode=update-lockfile"],
        ["dedupe brace-expansion --mode=update-lockfile", "dedupe <dep_name> --mode=update-lockfile"],
        ["remove brace-expansion --mode=update-lockfile", "remove <dep_name> --mode=update-lockfile"],
        env: { "YARN_NPM_MINIMAL_AGE_GATE" => "0" }
      )
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

  context "with unquoted Berry descriptors" do
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) do
      files = T.let(super(), T::Array[Dependabot::DependencyFile])
      files.map do |file|
        next file unless file.name == "yarn.lock"

        file.dup.tap { |copy| copy.content = T.must(file.content).gsub(/^"(brace-expansion@[^"]+)":$/, '\1:') }
      end
    end

    it "preserves installed versions for the scoped resolution" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
      expect(Dependabot::NpmAndYarn::Helpers).to have_received(:run_yarn_command).with(
        "install --mode=update-lockfile",
        fingerprint: "install",
        env: { "YARN_NPM_MINIMAL_AGE_GATE" => "0" }
      ).twice
    end

    context "when the experiment is disabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:enable_yarn_berry_conflicting_dependencies).and_return(false)
      end

      it "retains pruning and the legacy combined-version result" do
        expect(Dependabot::NpmAndYarn::Helpers).to receive(:run_yarn_command) do
          expect(File.read("yarn.lock")).not_to include("brace-expansion@npm:^2.0.2")
          File.write("yarn.lock", updated_lockfile_content)
          ""
        end

        expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("1.1.12"))
      end
    end

    context "without a scoped target version" do
      sig { returns(T.nilable(String)) }
      let(:target_version) { nil }

      it "retains pruning and uses the ordinary update command" do
        expect(Dependabot::NpmAndYarn::Helpers).to receive(:run_yarn_command).with(
          "up -R brace-expansion --mode=update-lockfile",
          fingerprint: "up -R <dependency_name> --mode=update-lockfile"
        ) do
          expect(File.read("yarn.lock")).not_to include("brace-expansion@npm:^2.0.2")
          File.write("yarn.lock", updated_lockfile_content)
          ""
        end

        expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
      end
    end
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

  context "with an alias installing a different package under the target's name" do
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) do
      files = T.let(super(), T::Array[Dependabot::DependencyFile])
      files.map do |file|
        next file unless file.name == "yarn.lock"

        content = T.must(file.content) + <<~YAML

          "brace-expansion@npm:other-package@^2.0.2":
            version: 2.1.2
            resolution: "other-package@npm:2.1.2"
        YAML
        file.dup.tap { |copy| copy.content = content }
      end
    end

    context "with an alias installing the targeted package" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:dependency_files) do
        files = T.let(super(), T::Array[Dependabot::DependencyFile])
        files.map do |file|
          next file unless file.name == "yarn.lock"

          content = T.must(file.content) + <<~YAML

            "my-brace@npm:brace-expansion@^2.0.2":
              version: 2.1.2
              resolution: "brace-expansion@npm:2.1.2"
          YAML
          file.dup.tap { |copy| copy.content = content }
        end
      end

      it "pins and restores both ordinary and aliased descriptors using the real package name" do
        allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_yarn_command) do
          manifest = JSON.parse(File.read("package.json"))
          if manifest.key?("resolutions")
            expect(manifest.fetch("resolutions")).to eq(
              "brace-expansion@npm:^2.0.2" => "npm:2.1.4",
              "my-brace@npm:brace-expansion@^2.0.2" => "npm:brace-expansion@2.1.4"
            )
            content = File.read("yarn.lock")
                          .gsub("2.1.2", "2.1.4")
                          .gsub("^2.0.2", "2.1.4")
            File.write("yarn.lock", content)
          else
            expect(File.read("yarn.lock")).to include(
              "brace-expansion@npm:^2.0.2",
              "my-brace@npm:brace-expansion@^2.0.2"
            )
          end
          ""
        end
        expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
      end

      context "when the alias pins the vulnerable version" do
        sig { returns(T::Array[Dependabot::DependencyFile]) }
        let(:dependency_files) do
          files = T.let(super(), T::Array[Dependabot::DependencyFile])
          files.map do |file|
            content = T.must(file.content).gsub(
              "my-brace@npm:brace-expansion@^2.0.2", "my-brace@npm:brace-expansion@2.1.2"
            )
            file.dup.tap { |copy| copy.content = content }
          end
        end

        it "rejects a target outside the alias requirement before installing" do
          expect(Dependabot::NpmAndYarn::Helpers).not_to receive(:run_yarn_command)
          expect { resolver.latest_resolvable_version }
            .to raise_error(Dependabot::DependencyFileNotResolvable, /incompatible requirement/)
        end
      end
    end

    it "does not treat the alias requirement as a requirement on the targeted package" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
    end

    it "collects only descriptors that install the real targeted package" do
      lockfile = T.must(dependency_files.find { |file| file.name == "yarn.lock" })
      expect(Dependabot::NpmAndYarn::FileParser::YarnLock.new(lockfile).versions_by_requirement(dependency.name)).to eq(
        "brace-expansion@npm:^1.1.7" => "1.1.12",
        "brace-expansion@npm:^2.0.2" => "2.1.2",
        "brace-expansion@npm:^5.0.2" => "5.0.2"
      )
    end
  end

  context "with another lockfile containing only an unrelated older version" do
    sig { returns(T::Array[Dependabot::DependencyFile]) }
    let(:dependency_files) do
      files = T.let(super(), T::Array[Dependabot::DependencyFile])
      lockfile = T.must(files.find { |file| file.name == "yarn.lock" })
      parsed = YAML.safe_load(T.must(lockfile.content))
      legacy_entries = parsed.select do |descriptor, _|
        descriptor == "__metadata" || descriptor.start_with?("legacy-parent@", "brace-expansion@npm:^1")
      end
      files + [
        Dependabot::DependencyFile.new(
          name: "unrelated/package.json",
          content: JSON.generate(
            "name" => "unrelated",
            "packageManager" => "yarn@4.9.1",
            "dependencies" => { "legacy-parent" => "1.0.0" }
          )
        ),
        Dependabot::DependencyFile.new(name: "unrelated/yarn.lock", content: YAML.dump(legacy_entries))
      ]
    end

    before do
      allow(Dependabot::Experiments).to receive(:enabled?).with(:enable_audit_fix_fallback).and_return(true)
      allow(Dependabot::NpmAndYarn::NativeHelpers).to receive(:run_yarn_audit_fix_command).and_return("")
      allow(Dependabot::NpmAndYarn::Helpers).to receive(:run_yarn_commands).and_return("")
    end

    it "skips unscoped updates and audit fallback for the unrelated lockfile during resolution" do
      expect(resolver.latest_resolvable_version).to eq(Dependabot::NpmAndYarn::Version.new("2.1.4"))
      expect(Dependabot::NpmAndYarn::Helpers).to have_received(:run_yarn_command).exactly(2).times
      expect(Dependabot::NpmAndYarn::NativeHelpers).not_to have_received(:run_yarn_audit_fix_command)
      expect(Dependabot::NpmAndYarn::Helpers).not_to have_received(:run_yarn_commands)
    end

    it "preserves the unrelated lockfile when generating security update files" do
      updated_dependency = Dependabot::Dependency.new(
        name: dependency.name,
        version: "2.1.4",
        previous_version: dependency.version,
        requirements: [],
        previous_requirements: [],
        package_manager: dependency.package_manager
      )
      updater = Dependabot::NpmAndYarn::FileUpdater::YarnLockfileUpdater.new(
        dependencies: [updated_dependency],
        dependency_files: dependency_files,
        credentials: [],
        repo_contents_path: nil,
        security_updates_only: true
      )
      targeted = T.must(dependency_files.find { |file| file.name == "yarn.lock" })
      unrelated = T.must(dependency_files.find { |file| file.name == "unrelated/yarn.lock" })

      expect(updater.updated_yarn_lock_content(targeted)).to include("brace-expansion@npm:2.1.4")
      expect(updater.updated_yarn_lock_content(unrelated)).to eq(unrelated.content)
      expect(Dependabot::NpmAndYarn::Helpers).to have_received(:run_yarn_command).exactly(2).times
      expect(Dependabot::NpmAndYarn::NativeHelpers).not_to have_received(:run_yarn_audit_fix_command)
      expect(Dependabot::NpmAndYarn::Helpers).not_to have_received(:run_yarn_commands)
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
