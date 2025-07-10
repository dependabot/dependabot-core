# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/vcpkg/package/package_details_fetcher"

RSpec.describe Dependabot::Vcpkg::Package::PackageDetailsFetcher do
  subject(:fetcher) do
    described_class.new(dependency: dependency)
  end

  let(:dependency_name) { "baseline" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: Dependabot::Vcpkg::Version.new("2025.06.13"),
      requirements: [{
        requirement: nil,
        groups: [],
        source: {
          type: "git",
          url: "https://github.com/microsoft/vcpkg.git"
        },
        file: "vcpkg.json"
      }],
      package_manager: "vcpkg"
    )
  end

  describe "#fetch" do
    subject(:details) { fetcher.fetch }

    context "when dependency is not a git dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "2025.06.13",
          requirements: [{
            requirement: nil,
            groups: [],
            source: nil,
            file: "vcpkg.json"
          }],
          package_manager: "vcpkg"
        )
      end

      it "returns nil" do
        expect(details).to be_nil
      end
    end

    context "when dependency is a git dependency" do
      let(:git_commit_checker) { instance_double(Dependabot::GitCommitChecker) }
      let(:mock_tags) do
        [
          {
            tag: "2025.06.13",
            version: Dependabot::Vcpkg::Version.new("2025.06.13"),
            commit_sha: "abc123",
            tag_sha: "def456"
          },
          {
            tag: "2025.04.09",
            version: Dependabot::Vcpkg::Version.new("2025.04.09"),
            commit_sha: "ghi789",
            tag_sha: "jkl012"
          }
        ]
      end

      before do
        allow(Dependabot::GitCommitChecker).to receive(:new).and_return(git_commit_checker)
        allow(git_commit_checker).to receive(:local_tags_for_allowed_versions).and_return(mock_tags)
      end

      it "returns package details with releases from git tags" do
        expect(details).to be_a(Dependabot::Package::PackageDetails)
        expect(details.dependency).to eq(dependency)
        expect(details.releases).not_to be_empty
        expect(details.releases.size).to eq(2)

        first_release = details.releases.first
        expect(first_release.version).to eq(Dependabot::Vcpkg::Version.new("2025.06.13"))
        expect(first_release.tag).to eq("2025.06.13")
        expect(first_release.released_at).to eq(Time.new(2025, 6, 13))
      end
    end

    context "when git repository is not reachable" do
      let(:git_commit_checker) { instance_double(Dependabot::GitCommitChecker) }

      before do
        allow(Dependabot::GitCommitChecker).to receive(:new).and_return(git_commit_checker)
        allow(git_commit_checker).to receive(:local_tags_for_allowed_versions)
          .and_raise(Dependabot::GitDependenciesNotReachable.new(["https://github.com/microsoft/vcpkg.git"]))
      end

      it "returns empty package details" do
        expect(details).to be_a(Dependabot::Package::PackageDetails)
        expect(details.dependency).to eq(dependency)
        expect(details.releases).to be_empty
      end
    end
  end

  describe "#extract_release_date" do
    it "extracts valid dates from vcpkg tag format" do
      expect(fetcher.send(:extract_release_date, "2025.06.13")).to eq(Time.new(2025, 6, 13))
      expect(fetcher.send(:extract_release_date, "2024.12.16")).to eq(Time.new(2024, 12, 16))
      expect(fetcher.send(:extract_release_date, "v2025.01.13")).to eq(Time.new(2025, 1, 13))
    end

    it "returns nil for invalid tag formats" do
      expect(fetcher.send(:extract_release_date, "invalid")).to be_nil
      expect(fetcher.send(:extract_release_date, "1.2.3")).to be_nil
    end
  end
end
