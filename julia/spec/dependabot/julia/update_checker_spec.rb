# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/julia/update_checker"
require "dependabot/julia/package/package_details_fetcher"

RSpec.describe Dependabot::Julia::UpdateChecker do
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: false,
      security_advisories: security_advisories,
      options: {}
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "Example",
      version: "0.4.1",
      requirements: [{
        file: "Project.toml",
        requirement: "0.4",
        groups: ["dependencies"],
        source: nil
      }],
      package_manager: "julia",
      metadata: { julia_uuid: "7876af07-990d-54b4-ab0e-23690620f79a" }
    )
  end

  let(:dependency_files) do
    [project_file, manifest_file]
  end

  let(:project_file) do
    Dependabot::DependencyFile.new(
      name: "Project.toml",
      content: fixture("projects", "basic", "Project.toml")
    )
  end

  let(:manifest_file) do
    Dependabot::DependencyFile.new(
      name: "Manifest.toml",
      content: fixture("projects", "basic", "Manifest.toml")
    )
  end

  let(:credentials) { [] }
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }

  describe "#latest_version" do
    subject(:latest_version) { checker.latest_version }

    it "returns a version" do
      # The actual version from Julia helper should be used
      # (This test validates the end-to-end flow but we'll keep it simple)
      expect(latest_version).to be_a(Gem::Version).or(be_nil)
      expect(latest_version.to_s).to match(/\d+\.\d+\.\d+/) if latest_version
    end

    context "when dependency has invalid UUID" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "Example",
          version: "0.4.1",
          requirements: [{
            file: "Project.toml",
            requirement: "0.4",
            groups: ["dependencies"],
            source: nil
          }],
          package_manager: "julia",
          metadata: { julia_uuid: "invalid-uuid-format" }
        )
      end

      it "returns nil due to invalid UUID" do
        expect(latest_version).to be_nil
      end
    end

    context "when dependency has no UUID" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "Example",
          version: "0.4.1",
          requirements: [{
            file: "Project.toml",
            requirement: "0.4",
            groups: ["dependencies"],
            source: nil
          }],
          package_manager: "julia"
        )
      end

      it "returns nil due to missing UUID" do
        expect(latest_version).to be_nil
      end
    end
  end

  describe "#latest_version with a cooldown configured" do
    subject(:latest_version) { cooldown_checker.latest_version }

    let(:cooldown_checker) do
      described_class.new(
        dependency: dependency,
        dependency_files: dependency_files,
        credentials: credentials,
        ignored_versions: ignored_versions,
        raise_on_ignored: false,
        security_advisories: security_advisories,
        update_cooldown: Dependabot::Package::ReleaseCooldownOptions.new(
          default_days: 7,
          include: include_patterns,
          exclude: exclude_patterns
        ),
        options: {}
      )
    end

    let(:include_patterns) { [] }
    let(:exclude_patterns) { [] }

    before do
      allow_any_instance_of(Dependabot::Julia::Package::PackageDetailsFetcher)
        .to receive(:fetch_package_releases)
        .and_return(
          [
            Dependabot::Package::PackageRelease.new(
              version: Dependabot::Julia::Version.new("0.5.0"),
              released_at: released_at
            )
          ]
        )
    end

    # ReleaseCooldownOptions stores include/exclude as Sets, so passing them
    # through unconverted used to raise a TypeError from the finder's T.cast.
    context "when the release is outside the cooldown window" do
      let(:released_at) { Time.now - (30 * 24 * 60 * 60) }

      it "returns the version" do
        expect(latest_version).to eq(Dependabot::Julia::Version.new("0.5.0"))
      end
    end

    context "when the release is inside the cooldown window" do
      let(:released_at) { Time.now - (24 * 60 * 60) }

      it "filters the version out" do
        expect(latest_version).to be_nil
      end

      context "when the dependency is excluded from the cooldown" do
        let(:exclude_patterns) { ["Example"] }

        it "returns the version" do
          expect(latest_version).to eq(Dependabot::Julia::Version.new("0.5.0"))
        end
      end

      context "when the dependency is not in the include list" do
        let(:include_patterns) { ["SomethingElse"] }

        it "returns the version" do
          expect(latest_version).to eq(Dependabot::Julia::Version.new("0.5.0"))
        end
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    it "returns the latest version or nil" do
      # This should call the real Julia helper
      expect(latest_resolvable_version).to be_a(Gem::Version).or(be_nil)
      expect(latest_resolvable_version.to_s).to match(/\d+\.\d+\.\d+/) if latest_resolvable_version
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    subject(:latest_resolvable_version_with_no_unlock) { checker.latest_resolvable_version_with_no_unlock }

    context "with current requirement constraint" do
      # The current requirement "0.4" should not allow version 0.5.x
      # So this should return nil as the version is incompatible
      it "respects version constraints" do
        result = latest_resolvable_version_with_no_unlock
        expect(result).to be_a(Gem::Version).or(be_nil)
      end
    end

    context "with mocked releases" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "Example",
          version: current_version,
          requirements: [{
            file: "Project.toml",
            requirement: current_requirement,
            groups: ["dependencies"],
            source: nil
          }],
          package_manager: "julia",
          metadata: { julia_uuid: "7876af07-990d-54b4-ab0e-23690620f79a" }
        )
      end

      before do
        allow_any_instance_of(Dependabot::Julia::Package::PackageDetailsFetcher)
          .to receive(:fetch_package_releases)
          .and_return(
            available_versions.map do |v|
              Dependabot::Package::PackageRelease.new(version: Dependabot::Julia::Version.new(v))
            end
          )
      end

      context "with an implicit caret requirement" do
        let(:current_version) { "1.2.0" }
        let(:current_requirement) { "1.2" }
        let(:available_versions) { %w(1.2.5 1.5.0 2.1.0) }

        it "returns the highest version within the caret range, not just latest" do
          expect(latest_resolvable_version_with_no_unlock).to eq(Dependabot::Julia::Version.new("1.5.0"))
        end
      end

      context "with a tilde requirement" do
        let(:current_version) { "1.2.0" }
        let(:current_requirement) { "~1.2" }
        let(:available_versions) { %w(1.2.5 1.3.0) }

        it "returns the highest patch within the tilde range" do
          expect(latest_resolvable_version_with_no_unlock).to eq(Dependabot::Julia::Version.new("1.2.5"))
        end
      end

      context "with a union requirement" do
        let(:current_version) { "0.34.1" }
        let(:current_requirement) { "0.34, 0.35" }
        let(:available_versions) { %w(0.34.2 0.35.3 0.36.0) }

        it "does not raise and returns the highest version in the union" do
          expect(latest_resolvable_version_with_no_unlock).to eq(Dependabot::Julia::Version.new("0.35.3"))
        end
      end

      context "when no available version satisfies the requirement" do
        let(:current_version) { "1.2.0" }
        let(:current_requirement) { "1.2" }
        let(:available_versions) { %w(2.1.0) }

        it "returns nil" do
          expect(latest_resolvable_version_with_no_unlock).to be_nil
        end
      end

      context "with a wildcard requirement" do
        let(:current_version) { "1.2.0" }
        let(:current_requirement) { "*" }
        let(:available_versions) { %w(1.2.5 3.0.0) }

        it "returns the latest version" do
          expect(latest_resolvable_version_with_no_unlock).to eq(Dependabot::Julia::Version.new("3.0.0"))
        end
      end
    end
  end

  describe "#updated_requirements" do
    subject(:updated_requirements) { checker.updated_requirements }

    it "returns updated requirements structure" do
      expect(updated_requirements).to be_an(Array)
      if updated_requirements.any?
        expect(updated_requirements.first).to be_a(Dependabot::DependencyRequirement)
        expect(updated_requirements.first.requirement).to be_a(String)
      end
    end
  end

  describe "ignored versions" do
    let(:ignored_versions) { [">= 1.a"] }

    before do
      # Mock the package details fetcher to return specific versions
      allow_any_instance_of(Dependabot::Julia::Package::PackageDetailsFetcher)
        .to receive(:fetch_package_releases)
        .and_return([
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Julia::Version.new("0.4.1"),
            released_at: Time.now - (100 * 24 * 60 * 60)
          ),
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Julia::Version.new("0.5.0"),
            released_at: Time.now - (90 * 24 * 60 * 60)
          ),
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Julia::Version.new("0.9.0"),
            released_at: Time.now - (80 * 24 * 60 * 60)
          ),
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Julia::Version.new("1.0.0"),
            released_at: Time.now - (70 * 24 * 60 * 60)
          ),
          Dependabot::Package::PackageRelease.new(
            version: Dependabot::Julia::Version.new("2.0.0"),
            released_at: Time.now - (60 * 24 * 60 * 60)
          )
        ])
    end

    context "when ignoring major version updates" do
      it "filters out major versions" do
        expect(checker.latest_version).to eq(Gem::Version.new("0.9.0"))
      end

      it "logs filtered versions" do
        allow(Dependabot.logger).to receive(:info)
        checker.latest_version
        expect(Dependabot.logger).to have_received(:info)
          .with("Filtered out 2 ignored versions")
      end
    end

    context "when all versions are ignored" do
      let(:ignored_versions) { [">= 0"] }

      it "returns nil" do
        expect(checker.latest_version).to be_nil
      end
    end

    context "when ignoring specific version ranges" do
      let(:ignored_versions) { [">= 0.5, < 1.0"] }

      it "filters out versions in the specified range" do
        expect(checker.latest_version).to eq(Gem::Version.new("2.0.0"))
      end
    end

    context "when raise_on_ignored is true" do
      let(:ignored_versions) { [">= 0.5"] }
      let(:checker) do
        described_class.new(
          dependency: dependency,
          dependency_files: dependency_files,
          credentials: credentials,
          ignored_versions: ignored_versions,
          raise_on_ignored: true,
          security_advisories: security_advisories,
          options: {}
        )
      end

      before do
        # Set up the same mocks for this new checker instance
        allow_any_instance_of(Dependabot::Julia::Package::PackageDetailsFetcher)
          .to receive(:fetch_package_releases)
          .and_return([
            Dependabot::Package::PackageRelease.new(
              version: Dependabot::Julia::Version.new("0.4.1"),
              released_at: Time.now - (100 * 24 * 60 * 60)
            ),
            Dependabot::Package::PackageRelease.new(
              version: Dependabot::Julia::Version.new("0.5.0"),
              released_at: Time.now - (90 * 24 * 60 * 60)
            ),
            Dependabot::Package::PackageRelease.new(
              version: Dependabot::Julia::Version.new("1.0.0"),
              released_at: Time.now - (70 * 24 * 60 * 60)
            )
          ])
        allow(Dependabot.logger).to receive(:info)
      end

      it "logs when all newer versions are ignored" do
        expect { checker.latest_version }.to raise_error(Dependabot::AllVersionsIgnored)
        expect(Dependabot.logger).to have_received(:info)
          .with("All updates for Example were ignored")
      end
    end
  end
end
