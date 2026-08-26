# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/package/release_cooldown_options"
require "dependabot/security_advisory"
require "dependabot/uv/update_checker/lock_file_resolver"

RSpec.describe Dependabot::Uv::UpdateChecker::LockFileResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      repo_contents_path: nil,
      security_advisories: security_advisories,
      ignored_versions: ignored_versions
    )
  end

  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  let(:security_advisories) { [] }
  let(:ignored_versions) { [] }

  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "uv.lock",
        content: fixture("uv_locks", "simple.lock")
      ),
      Dependabot::DependencyFile.new(
        name: "pyproject.toml",
        content: fixture("pyproject_files", "uv_simple.toml")
      )
    ]
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "requests",
      version: "2.32.3",
      requirements: [{
        file: "uv.lock",
        requirement: ">=2.31.0",
        groups: [],
        source: nil
      }],
      package_manager: "uv"
    )
  end

  describe "#latest_resolvable_version" do
    let(:available_releases) { [package_release("2.33.0"), package_release("2.34.0")] }
    let(:eligible_releases) { available_releases }
    let(:latest_version_finder) do
      instance_double(
        Dependabot::Uv::UpdateChecker::LatestVersionFinder,
        available_versions: available_releases,
        eligible_releases: eligible_releases
      )
    end

    before do
      allow(Dependabot::Uv::UpdateChecker::LatestVersionFinder)
        .to receive(:new).and_return(latest_version_finder)
      allow(Dependabot::Uv::FileUpdater::LockFileUpdater)
        .to receive(:new) do |target_requirement:, **_args|
          target_version =
            if target_requirement.start_with?("==")
              target_requirement.delete_prefix("==")
            elsif target_requirement.include?("!=2.33.0")
              "2.34.0"
            else
              "2.33.0"
            end
          instance_double(
            Dependabot::Uv::FileUpdater::LockFileUpdater,
            updated_dependency_files: [resolved_lockfile(target_version)]
          )
        end
    end

    context "when requirement is nil" do
      it "returns nil" do
        expect(resolver.latest_resolvable_version(requirement: nil)).to be_nil
        expect(Dependabot::Uv::FileUpdater::LockFileUpdater).not_to have_received(:new)
      end
    end

    context "when requirement is satisfied by the current version" do
      it "returns the version selected by uv" do
        result = resolver.latest_resolvable_version(requirement: ">=2.30.0")
        expect(result.to_s).to eq("2.33.0")
      end
    end

    context "when requirement is not satisfied by the current version" do
      it "returns nil" do
        result = resolver.latest_resolvable_version(requirement: ">=3.0.0")
        expect(result).to be_nil
      end
    end

    context "when no newer allowed version exists" do
      let(:eligible_releases) { [] }

      it "returns the current version without running uv" do
        result = resolver.latest_resolvable_version(requirement: ">=2.30.0,<=2.32.3")
        expect(result.to_s).to eq("2.32.3")
        expect(Dependabot::Uv::FileUpdater::LockFileUpdater).not_to have_received(:new)
      end
    end

    context "when a version inside the range is ignored" do
      let(:eligible_releases) { [package_release("2.34.0")] }

      it "excludes the ignored version from native resolution" do
        result = resolver.latest_resolvable_version(requirement: ">=2.30.0,<=2.34.0")

        expect(result.to_s).to eq("2.34.0")
        expect(Dependabot::Uv::FileUpdater::LockFileUpdater)
          .to have_received(:new).with(hash_including(target_requirement: ">=2.30.0,<=2.34.0,!=2.33.0"))
      end
    end

    context "when all newer versions are filtered out" do
      let(:eligible_releases) { [] }

      it "returns the current version without running uv" do
        result = resolver.latest_resolvable_version(requirement: ">=2.30.0")

        expect(result.to_s).to eq("2.32.3")
        expect(Dependabot::Uv::FileUpdater::LockFileUpdater).not_to have_received(:new)
      end
    end

    context "when only a vulnerable intermediate version resolves" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "requests",
            package_manager: "uv",
            vulnerable_versions: ["== 2.33.0"]
          )
        ]
      end

      before do
        allow(Dependabot::Uv::FileUpdater::LockFileUpdater)
          .to receive(:new) do |target_requirement:, **_args|
            updater = instance_double(Dependabot::Uv::FileUpdater::LockFileUpdater)
            if target_requirement.include?("!=2.33.0")
              allow(updater).to receive(:updated_dependency_files).and_raise(
                Dependabot::DependencyFileNotResolvable,
                "× No solution found when resolving dependencies"
              )
            else
              allow(updater).to receive(:updated_dependency_files)
                .and_return([resolved_lockfile("2.33.0")])
            end
            updater
          end
      end

      it "excludes the vulnerable version from fallback resolution" do
        result = resolver.latest_resolvable_version(requirement: ">=2.30.0,<=2.34.0")

        expect(result.to_s).to eq("2.32.3")
        expect(Dependabot::Uv::FileUpdater::LockFileUpdater)
          .to have_received(:new).with(hash_including(target_requirement: ">=2.30.0,<=2.34.0,!=2.33.0"))
      end
    end

    it "memoizes the result by requirement" do
      2.times { resolver.latest_resolvable_version(requirement: ">=2.30.0") }

      expect(Dependabot::Uv::FileUpdater::LockFileUpdater).to have_received(:new).once
    end

    context "when the lockfile does not change" do
      before do
        updater = instance_double(Dependabot::Uv::FileUpdater::LockFileUpdater)
        allow(updater).to receive(:updated_dependency_files)
          .and_raise(Dependabot::DependencyFileContentNotChanged, "Expected lockfile to change!")
        allow(Dependabot::Uv::FileUpdater::LockFileUpdater).to receive(:new).and_return(updater)
      end

      it "returns the version already present in the lockfile" do
        result = resolver.latest_resolvable_version(requirement: ">=2.30.0")
        expect(result.to_s).to eq("2.32.3")
      end
    end

    context "when an operational error occurs" do
      before do
        updater = instance_double(Dependabot::Uv::FileUpdater::LockFileUpdater)
        allow(updater).to receive(:updated_dependency_files)
          .and_raise(Dependabot::DependencyFileNotResolvable, "Failed to find workspace member")
        allow(Dependabot::Uv::FileUpdater::LockFileUpdater).to receive(:new).and_return(updater)
      end

      it "propagates the classified error" do
        expect { resolver.latest_resolvable_version(requirement: ">=2.30.0") }
          .to raise_error(Dependabot::DependencyFileNotResolvable, /workspace member/)
      end
    end

    context "when native resolution has a version conflict" do
      before do
        updater = instance_double(Dependabot::Uv::FileUpdater::LockFileUpdater)
        allow(updater).to receive(:updated_dependency_files).and_raise(
          Dependabot::DependencyFileNotResolvable,
          "× No solution found when resolving dependencies"
        )
        allow(Dependabot::Uv::FileUpdater::LockFileUpdater).to receive(:new).and_return(updater)
      end

      it "returns the current version" do
        result = resolver.latest_resolvable_version(requirement: ">=2.30.0")
        expect(result.to_s).to eq("2.32.3")
      end
    end

    context "when uv updates multiple locked occurrences" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.19.0",
          requirements: [],
          package_manager: "uv"
        )
      end
      let(:dependency_files) do
        [
          resolved_lockfile_with_versions("2.19.0", "2.20.0"),
          Dependabot::DependencyFile.new(
            name: "pyproject.toml",
            content: fixture("pyproject_files", "uv_simple.toml")
          )
        ]
      end
      let(:available_releases) { [package_release("2.20.0"), package_release("2.21.0")] }

      before do
        allow(Dependabot::Uv::FileUpdater::LockFileUpdater)
          .to receive(:new).and_return(
            instance_double(
              Dependabot::Uv::FileUpdater::LockFileUpdater,
              updated_dependency_files: [resolved_lockfile_with_versions("2.20.0", "2.21.0")]
            )
          )
      end

      it "returns the lowest updated occurrence parsed by DependencySet" do
        result = resolver.latest_resolvable_version(requirement: ">=2.19.0,<=2.21.0")
        expect(result.to_s).to eq("2.20.0")
      end
    end
  end

  describe "#resolvable?" do
    before do
      allow(Dependabot::Uv::FileUpdater::LockFileUpdater)
        .to receive(:new) do |**_args|
          instance_double(
            Dependabot::Uv::FileUpdater::LockFileUpdater,
            updated_dependency_files: [resolved_lockfile("2.33.0")]
          )
        end
    end

    it "verifies and memoizes the locked version" do
      2.times { expect(resolver.resolvable?(version: Dependabot::Uv::Version.new("2.34.0"))).to be(false) }

      expect(Dependabot::Uv::FileUpdater::LockFileUpdater).to have_received(:new).once
      expect(Dependabot::Uv::FileUpdater::LockFileUpdater)
        .to have_received(:new).with(hash_including(target_requirement: "==2.34.0"))
    end

    context "when another locked occurrence already has the target version" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.19.0",
          requirements: [],
          package_manager: "uv"
        )
      end
      let(:dependency_files) do
        [
          resolved_lockfile_with_versions("2.19.0", "2.20.0"),
          Dependabot::DependencyFile.new(
            name: "pyproject.toml",
            content: fixture("pyproject_files", "uv_simple.toml")
          )
        ]
      end

      before do
        allow(Dependabot::Uv::FileUpdater::LockFileUpdater)
          .to receive(:new).and_return(
            instance_double(
              Dependabot::Uv::FileUpdater::LockFileUpdater,
              updated_dependency_files: [resolved_lockfile_with_versions("2.19.0", "2.20.0")]
            )
          )
      end

      it "does not treat the other occurrence as the updated dependency" do
        expect(resolver.resolvable?(version: Dependabot::Uv::Version.new("2.20.0"))).to be(false)
      end

      context "when uv replaces the current occurrence" do
        before do
          allow(Dependabot::Uv::FileUpdater::LockFileUpdater)
            .to receive(:new).and_return(
              instance_double(
                Dependabot::Uv::FileUpdater::LockFileUpdater,
                updated_dependency_files: [resolved_lockfile_with_versions("2.20.0", "2.20.0")]
              )
            )
        end

        it "recognizes the increased target occurrence count" do
          expect(resolver.resolvable?(version: Dependabot::Uv::Version.new("2.20.0"))).to be(true)
        end
      end

      context "when one duplicate current occurrence remains" do
        let(:dependency_files) do
          [
            resolved_lockfile_with_versions("2.19.0", "2.19.0"),
            Dependabot::DependencyFile.new(
              name: "pyproject.toml",
              content: fixture("pyproject_files", "uv_simple.toml")
            )
          ]
        end

        before do
          allow(Dependabot::Uv::FileUpdater::LockFileUpdater)
            .to receive(:new).and_return(
              instance_double(
                Dependabot::Uv::FileUpdater::LockFileUpdater,
                updated_dependency_files: [resolved_lockfile_with_versions("2.19.0", "2.20.0")]
              )
            )
        end

        it "does not report the higher occurrence as the dependency update" do
          expect(resolver.resolvable?(version: Dependabot::Uv::Version.new("2.20.0"))).to be(false)
        end
      end
    end
  end

  describe "#lowest_resolvable_security_fix_version" do
    let(:pypi_url) { "https://pypi.org/simple/requests/" }
    let(:pypi_response) do
      fixture("pypi", "pypi_simple_response_requests.html")
    end

    before do
      stub_request(:get, pypi_url)
        .to_return(status: 200, body: pypi_response)
      allow(resolver).to receive(:resolvable?).and_return(true)
    end

    context "with no security advisories" do
      let(:security_advisories) { [] }

      it "returns nil when there are no advisories" do
        expect(resolver.lowest_resolvable_security_fix_version).to be_nil
      end
    end

    context "with a security advisory" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "2.0.0",
          requirements: [{
            file: "uv.lock",
            requirement: ">=2.0.0",
            groups: [],
            source: nil
          }],
          package_manager: "uv"
        )
      end

      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "requests",
            package_manager: "uv",
            vulnerable_versions: ["<= 2.1.0"]
          )
        ]
      end

      it "returns the lowest non-vulnerable version" do
        result = resolver.lowest_resolvable_security_fix_version
        expect(result).not_to be_nil
        expect(result).to be_a(Dependabot::Uv::Version)
        # Should return a version > 2.1.0
        expect(result).to be > Dependabot::Uv::Version.new("2.1.0")
      end
    end

    context "with multiple security advisories" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "1.0.0",
          requirements: [{
            file: "uv.lock",
            requirement: ">=1.0.0",
            groups: [],
            source: nil
          }],
          package_manager: "uv"
        )
      end

      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "requests",
            package_manager: "uv",
            vulnerable_versions: ["< 2.0.0"]
          ),
          Dependabot::SecurityAdvisory.new(
            dependency_name: "requests",
            package_manager: "uv",
            vulnerable_versions: ["< 2.5.0"]
          )
        ]
      end

      it "returns the lowest version that fixes all advisories" do
        result = resolver.lowest_resolvable_security_fix_version
        expect(result).not_to be_nil
        expect(result).to be_a(Dependabot::Uv::Version)
        # Should return a version >= 2.5.0
        expect(result).to be >= Dependabot::Uv::Version.new("2.5.0")
      end
    end

    context "with ignored versions" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "requests",
          version: "1.0.0",
          requirements: [{
            file: "uv.lock",
            requirement: ">=1.0.0",
            groups: [],
            source: nil
          }],
          package_manager: "uv"
        )
      end

      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "requests",
            package_manager: "uv",
            vulnerable_versions: ["< 2.0.0"]
          )
        ]
      end
      let(:ignored_versions) { [">= 2.30.0"] }

      it "respects ignored versions when finding security fix" do
        result = resolver.lowest_resolvable_security_fix_version
        expect(result).not_to be_nil
        # Should return a version < 2.30.0
        expect(result).to be < Dependabot::Uv::Version.new("2.30.0")
      end
    end

    context "when the lowest security fix is not resolvable" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: "requests",
            package_manager: "uv",
            vulnerable_versions: ["<= 2.1.0"]
          )
        ]
      end

      before do
        allow(resolver).to receive(:resolvable?).and_return(false)
      end

      it "returns nil" do
        expect(resolver.lowest_resolvable_security_fix_version).to be_nil
      end
    end
  end

  describe "cooldown support" do
    let(:cooldown_options) do
      Dependabot::Package::ReleaseCooldownOptions.new(
        default_days: 7
      )
    end

    let(:resolver_with_cooldown) do
      described_class.new(
        dependency: dependency,
        dependency_files: dependency_files,
        credentials: credentials,
        repo_contents_path: nil,
        security_advisories: security_advisories,
        ignored_versions: ignored_versions,
        update_cooldown: cooldown_options
      )
    end

    it "passes cooldown_options to LatestVersionFinder" do
      expect(Dependabot::Uv::UpdateChecker::LatestVersionFinder)
        .to receive(:new)
        .with(hash_including(cooldown_options: cooldown_options))
        .and_call_original

      # Trigger creation of the LatestVersionFinder via a public method
      pypi_url = "https://pypi.org/simple/requests/"
      pypi_response = fixture("pypi", "pypi_simple_response_requests.html")
      stub_request(:get, pypi_url).to_return(status: 200, body: pypi_response)

      resolver_with_cooldown.lowest_resolvable_security_fix_version
    end

    it "passes cooldown_options: nil when update_cooldown is nil" do
      expect(Dependabot::Uv::UpdateChecker::LatestVersionFinder)
        .to receive(:new)
        .with(hash_including(cooldown_options: nil))
        .and_call_original

      pypi_url = "https://pypi.org/simple/requests/"
      pypi_response = fixture("pypi", "pypi_simple_response_requests.html")
      stub_request(:get, pypi_url).to_return(status: 200, body: pypi_response)

      resolver.lowest_resolvable_security_fix_version
    end
  end

  def resolved_lockfile(version)
    resolved_lockfile_with_versions(version)
  end

  def package_release(version)
    Dependabot::Package::PackageRelease.new(
      version: Dependabot::Uv::Version.new(version),
      released_at: nil,
      tag: nil
    )
  end

  def resolved_lockfile_with_versions(*versions)
    Dependabot::DependencyFile.new(
      name: "uv.lock",
      content: <<~TOML
        version = 1

        #{versions.map do |version|
          <<~PACKAGE
            [[package]]
            name = "#{dependency.name}"
            version = "#{version}"
          PACKAGE
        end.join("\n")}
      TOML
    )
  end
end
