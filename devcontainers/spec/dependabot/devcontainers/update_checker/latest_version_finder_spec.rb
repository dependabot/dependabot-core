# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/devcontainers/update_checker/latest_version_finder"
require "dependabot/devcontainers/requirement"

namespace = Dependabot::Devcontainers::UpdateChecker
RSpec.describe namespace::LatestVersionFinder do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "ghcr.io/codspace/versioning/foo",
      version: "1.2.0",
      requirements: [{
        file: "devcontainers.json",
        requirement: ">=1.2.0",
        groups: [],
        source: nil

      }],
      package_manager: "devcontainers"
    )
  end

  let(:raise_on_ignored) { false }
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }
  let(:dependency_files) { [] }

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: github_credentials,
      security_advisories: security_advisories,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored,
      cooldown_options: cooldown_options
    )
  end
  let(:cooldown_options) { nil }

  describe "#release_versions" do
    subject(:release_versions) do
      checker.release_versions
    end

    let(:response) { fixture("projects/devcontainers_json", "devcontainers-parser.json") }

    before do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return(response)
    end

    context "when fetches the records" do
      it "returns an array of releases" do
        release = release_versions.first

        expect(release_versions).to be_an_instance_of(Array)
        expect(release).to be_a(Dependabot::Devcontainers::Version)
        expect(release.version).to eq("2")
      end
    end

    context "when fetching the records fails" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_return(
          StandardError.new("Command failed")
        )
      end

      it "returns current dependency version" do
        release = release_versions.first

        expect(release).to be_a(Dependabot::Devcontainers::Version)
        expect(release.version).to eq("1.2.0")
      end
    end

    context "when cooldown is configured and the release date is unavailable" do
      let(:cooldown_options) do
        Dependabot::Package::ReleaseCooldownOptions.new(default_days: 7)
      end
      let(:release) do
        Dependabot::Package::PackageRelease.new(
          version: Dependabot::Devcontainers::Version.new("2.0.0"),
          released_at: nil
        )
      end
      let(:package_details_fetcher) do
        instance_double(
          Dependabot::Devcontainers::Package::PackageDetailsFetcher,
          fetch_package_releases: [release],
          fetch_release_metadata: release
        )
      end

      before do
        allow(Dependabot::Devcontainers::Package::PackageDetailsFetcher)
          .to receive(:new).with(dependency: dependency).and_return(package_details_fetcher)
      end

      it "allows the release and marks the dependency" do
        expect(release_versions.map(&:to_s)).to eq(["2.0.0"])
        expect(dependency.metadata[:cooldown_date_unavailable]).to be(true)
      end
    end
  end
end
