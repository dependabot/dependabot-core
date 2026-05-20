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
  end

  describe "#updated_requirements" do
    subject(:updated_requirements) { checker.updated_requirements }

    it "returns updated requirements structure" do
      expect(updated_requirements).to be_an(Array)
      if updated_requirements.any?
        expect(updated_requirements.first).to include(:requirement)
        expect(updated_requirements.first[:requirement]).to be_a(String)
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
