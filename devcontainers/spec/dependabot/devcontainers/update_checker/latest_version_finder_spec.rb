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
      raise_on_ignored: raise_on_ignored
    )
  end

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
  end
end
