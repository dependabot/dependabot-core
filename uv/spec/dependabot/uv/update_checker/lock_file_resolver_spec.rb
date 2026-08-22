# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/package/package_release"
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
      ignored_versions: ignored_versions,
      update_cooldown: update_cooldown
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
  let(:update_cooldown) { nil }

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
    let(:available_version_strings) { ["2.32.3", "2.33.0"] }
    let(:available_versions) do
      available_version_strings.map do |v|
        Dependabot::Package::PackageRelease.new(version: Dependabot::Uv::Version.new(v))
      end
    end
    # By default nothing is in cooldown (update_cooldown is nil), so every available
    # release is a candidate.
    let(:latest_version_finder) do
      instance_double(
        Dependabot::Uv::UpdateChecker::LatestVersionFinder,
        available_versions: available_versions
      )
    end

    before do
      allow(Dependabot::Uv::UpdateChecker::LatestVersionFinder)
        .to receive(:new).and_return(latest_version_finder)
    end

    context "when requirement is nil" do
      it "returns nil" do
        expect(resolver.latest_resolvable_version(requirement: nil)).to be_nil
      end
    end

    context "when a newer version is resolvable" do
      before do
        lock_updater = instance_double(
          Dependabot::Uv::FileUpdater::LockFileUpdater,
          updated_dependency_files: []
        )
        allow(Dependabot::Uv::FileUpdater::LockFileUpdater)
          .to receive(:new).and_return(lock_updater)
      end

      it "returns the highest resolvable version" do
        result = resolver.latest_resolvable_version(requirement: ">=2.30.0")
        expect(result.to_s).to eq("2.33.0")
      end
    end

    context "when the highest version conflicts but a lower one resolves" do
      let(:available_version_strings) { ["2.32.3", "2.33.0", "2.34.0"] }

      before do
        allow(Dependabot::Uv::FileUpdater::LockFileUpdater)
          .to receive(:new) do |dependencies:, **_rest|
            target = dependencies.first.version
            if target == "2.34.0"
              raise Dependabot::DependencyFileNotResolvable,
                    "No solution found when resolving dependencies"
            end

            instance_double(
              Dependabot::Uv::FileUpdater::LockFileUpdater,
              updated_dependency_files: []
            )
          end
      end

      it "falls back to the next highest resolvable version" do
        result = resolver.latest_resolvable_version(requirement: ">=2.30.0")
        expect(result.to_s).to eq("2.33.0")
      end
    end

    context "when the requirement upper bound excludes the latest release" do
      let(:available_version_strings) { ["2.32.3", "2.33.0", "3.0.0"] }

      before do
        lock_updater = instance_double(
          Dependabot::Uv::FileUpdater::LockFileUpdater,
          updated_dependency_files: []
        )
        allow(Dependabot::Uv::FileUpdater::LockFileUpdater)
          .to receive(:new).and_return(lock_updater)
      end

      it "returns the highest version within the requirement" do
        result = resolver.latest_resolvable_version(requirement: ">=2.30.0,<3")
        expect(result.to_s).to eq("2.33.0")
      end
    end

    context "when ignore conditions exclude the newer version" do
      let(:ignored_versions) { [">= 2.33.0"] }

      before do
        lock_updater = instance_double(
          Dependabot::Uv::FileUpdater::LockFileUpdater,
          updated_dependency_files: []
        )
        allow(Dependabot::Uv::FileUpdater::LockFileUpdater)
          .to receive(:new).and_return(lock_updater)
      end

      it "falls back to the current version" do
        result = resolver.latest_resolvable_version(requirement: ">=2.30.0")
        expect(result.to_s).to eq("2.32.3")
      end
    end

    context "when no newer version is resolvable" do
      before do
        lock_updater = instance_double(Dependabot::Uv::FileUpdater::LockFileUpdater)
        allow(lock_updater).to receive(:updated_dependency_files)
          .and_raise(Dependabot::DependencyFileNotResolvable, "No solution found when resolving dependencies")
        allow(Dependabot::Uv::FileUpdater::LockFileUpdater)
          .to receive(:new).and_return(lock_updater)
      end

      it "falls back to the current version" do
        result = resolver.latest_resolvable_version(requirement: ">=2.30.0")
        expect(result.to_s).to eq("2.32.3")
      end
    end

    context "when a non-conflict resolution error occurs" do
      before do
        lock_updater = instance_double(Dependabot::Uv::FileUpdater::LockFileUpdater)
        allow(lock_updater).to receive(:updated_dependency_files)
          .and_raise(Dependabot::DependencyFileNotResolvable, "Failed to find workspace member")
        allow(Dependabot::Uv::FileUpdater::LockFileUpdater)
          .to receive(:new).and_return(lock_updater)
      end

      it "propagates the error instead of silently reporting no update" do
        expect { resolver.latest_resolvable_version(requirement: ">=2.30.0") }
          .to raise_error(Dependabot::DependencyFileNotResolvable, /workspace member/)
      end
    end

    context "when an operational error occurs during resolution" do
      before do
        lock_updater = instance_double(Dependabot::Uv::FileUpdater::LockFileUpdater)
        allow(lock_updater).to receive(:updated_dependency_files)
          .and_raise(Dependabot::PrivateSourceAuthenticationFailure, "pypi.example.com")
        allow(Dependabot::Uv::FileUpdater::LockFileUpdater)
          .to receive(:new).and_return(lock_updater)
      end

      it "propagates the error instead of silently reporting no update" do
        expect { resolver.latest_resolvable_version(requirement: ">=2.30.0") }
          .to raise_error(Dependabot::PrivateSourceAuthenticationFailure)
      end
    end

    context "when a newer release is yanked" do
      let(:available_version_strings) { ["2.32.3", "2.33.0"] }
      let(:available_versions) do
        [
          Dependabot::Package::PackageRelease.new(version: Dependabot::Uv::Version.new("2.32.3")),
          Dependabot::Package::PackageRelease.new(version: Dependabot::Uv::Version.new("2.33.0"), yanked: true)
        ]
      end

      before do
        lock_updater = instance_double(
          Dependabot::Uv::FileUpdater::LockFileUpdater,
          updated_dependency_files: []
        )
        allow(Dependabot::Uv::FileUpdater::LockFileUpdater)
          .to receive(:new).and_return(lock_updater)
      end

      it "skips the yanked version and falls back to the current version" do
        result = resolver.latest_resolvable_version(requirement: ">=2.30.0")
        expect(result.to_s).to eq("2.32.3")
      end
    end

    context "when a lower release is in cooldown while a higher one is allowed" do
      # Mirrors the backport case: a lower version can be released later and thus be in
      # cooldown while a higher, older version is allowed. Cooldown is per release date,
      # not a version range, so the in-cooldown version must be excluded outright.
      let(:update_cooldown) do
        Dependabot::Package::ReleaseCooldownOptions.new(default_days: 90)
      end
      let(:available_versions) do
        [
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Uv::Version.new("2.32.3"), released_at: Time.now - (300 * 24 * 60 * 60)
          ),
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Uv::Version.new("2.33.0"), released_at: Time.now
          ),
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Uv::Version.new("2.34.0"), released_at: Time.now - (200 * 24 * 60 * 60)
          )
        ]
      end

      before do
        allow(Dependabot::Uv::FileUpdater::LockFileUpdater)
          .to receive(:new).and_return(
            instance_double(Dependabot::Uv::FileUpdater::LockFileUpdater, updated_dependency_files: [])
          )
      end

      it "never probes or returns the in-cooldown version" do
        result = resolver.latest_resolvable_version(requirement: ">=2.30.0")
        expect(result.to_s).to eq("2.34.0")
        expect(Dependabot::Uv::FileUpdater::LockFileUpdater)
          .to have_received(:new)
          .with(hash_including(dependencies: [have_attributes(version: "2.34.0")]))
        expect(Dependabot::Uv::FileUpdater::LockFileUpdater)
          .not_to have_received(:new)
          .with(hash_including(dependencies: [have_attributes(version: "2.33.0")]))
      end
    end

    context "when only a lower candidate resolves after several conflicts" do
      let(:available_version_strings) do
        ["2.32.3", "2.33.0", "2.34.0", "2.35.0", "2.36.0", "2.37.0", "2.38.0"]
      end

      before do
        allow(Dependabot::Uv::FileUpdater::LockFileUpdater)
          .to receive(:new) do |dependencies:, **_rest|
            target = dependencies.first.version
            instance_double(Dependabot::Uv::FileUpdater::LockFileUpdater).tap do |updater|
              if target == "2.33.0"
                allow(updater).to receive(:updated_dependency_files).and_return([])
              else
                allow(updater).to receive(:updated_dependency_files)
                  .and_raise(Dependabot::DependencyFileNotResolvable,
                             "No solution found when resolving dependencies")
              end
            end
          end
      end

      it "keeps probing past the highest conflicts and returns the resolvable version" do
        result = resolver.latest_resolvable_version(requirement: ">=2.30.0")
        expect(result.to_s).to eq("2.33.0")
      end
    end

    context "when there are no newer versions available" do
      let(:available_version_strings) { ["2.31.0", "2.32.3"] }

      it "returns the current version when it satisfies the requirement" do
        result = resolver.latest_resolvable_version(requirement: ">=2.30.0")
        expect(result.to_s).to eq("2.32.3")
      end
    end

    context "when requirement is not satisfied by the current version" do
      let(:available_version_strings) { ["2.32.3"] }

      it "returns nil" do
        result = resolver.latest_resolvable_version(requirement: ">=3.0.0")
        expect(result).to be_nil
      end
    end
  end

  describe "#resolvable?" do
    it "returns true for any version" do
      expect(resolver.resolvable?(version: "2.32.3")).to be(true)
      expect(resolver.resolvable?(version: "999.0.0")).to be(true)
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
end
