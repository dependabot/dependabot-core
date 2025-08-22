# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/vcpkg/package/package_details_fetcher"

RSpec.describe Dependabot::Vcpkg::Package::PackageDetailsFetcher do
  subject(:fetcher) do
    described_class.new(dependency: dependency)
  end

  let(:dependency_name) { "github.com/microsoft/vcpkg" }
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
          name: "curl",
          version: "8.10.0",
          requirements: [{
            requirement: ">=8.10.0",
            groups: [],
            source: nil,
            file: "vcpkg.json"
          }],
          package_manager: "vcpkg"
        )
      end

      before do
        # Mock the git commands that would be run in /opt/vcpkg
        allow(Dir).to receive(:chdir).with("/opt/vcpkg").and_yield
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command) do |cmd|
          case cmd
          when %r{git log --format=%H --follow -- ports/curl/vcpkg\.json}
            <<~GIT
              abc123def456789012345678901234567890abcd
              def4561237890123456789012345678901abcdef
              abc7890123456789012345678901abcdef123456
            GIT
          when "git show abc123def456789012345678901234567890abcd:ports/curl/vcpkg.json"
            '{"name": "curl", "version": "8.15.0", "port-version": 1}'
          when "git show def4561237890123456789012345678901abcdef:ports/curl/vcpkg.json"
            '{"name": "curl", "version": "8.14.0"}'
          when "git show abc7890123456789012345678901abcdef123456:ports/curl/vcpkg.json"
            '{"name": "curl", "version": "8.10.0"}'
          when "git show -s --format=%ci abc123def456789012345678901234567890abcd"
            "2025-01-15 10:30:00 +0000"
          when "git show -s --format=%ci def4561237890123456789012345678901abcdef"
            "2025-01-10 14:20:00 +0000"
          when "git show -s --format=%ci abc7890123456789012345678901abcdef123456"
            "2025-01-05 09:15:00 +0000"
          else
            raise Dependabot::SharedHelpers::HelperSubprocessFailed.new("Command failed: #{cmd}", "Mock error")
          end
        end
      end

      it "returns package details with releases from port history" do
        expect(details).to be_a(Dependabot::Package::PackageDetails)
        expect(details.dependency).to eq(dependency)
        expect(details.releases).not_to be_empty
        expect(details.releases.size).to eq(3)

        latest_release = details.releases.first
        expect(latest_release.version.to_s).to eq("8.15.0#1")
        expect(latest_release.tag).to eq("8.15.0#1")
        expect(latest_release.details["base_version"]).to eq("8.15.0")
        expect(latest_release.details["port_version"]).to eq(1)

        second_release = details.releases[1]
        expect(second_release.version.to_s).to eq("8.14.0")
        expect(second_release.tag).to eq("8.14.0")
        expect(second_release.details["base_version"]).to eq("8.14.0")
        expect(second_release.details["port_version"]).to eq(0)
      end
    end

    context "when dependency is not a git dependency and git commands fail" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "nonexistent",
          version: "1.0.0",
          requirements: [{
            requirement: ">=1.0.0",
            groups: [],
            source: nil,
            file: "vcpkg.json"
          }],
          package_manager: "vcpkg"
        )
      end

      before do
        allow(Dir).to receive(:chdir).with("/opt/vcpkg").and_yield
        allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
          .and_raise(Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                       message: "Command failed: Port not found",
                       error_context: { command: "git log" }
                     ))
      end

      it "returns empty package details" do
        expect(details).to be_a(Dependabot::Package::PackageDetails)
        expect(details.dependency).to eq(dependency)
        expect(details.releases).to be_empty
      end
    end

    context "when dependency is a baseline git dependency" do
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

  describe "#extract_release_date_from_tag" do
    it "extracts valid dates from vcpkg tag format" do
      expect(fetcher.send(:extract_release_date_from_tag, "2025.06.13")).to eq(Time.new(2025, 6, 13))
      expect(fetcher.send(:extract_release_date_from_tag, "2024.12.16")).to eq(Time.new(2024, 12, 16))
      expect(fetcher.send(:extract_release_date_from_tag, "v2025.01.13")).to eq(Time.new(2025, 1, 13))
    end

    it "returns nil for invalid tag formats" do
      expect(fetcher.send(:extract_release_date_from_tag, "invalid")).to be_nil
      expect(fetcher.send(:extract_release_date_from_tag, "1.2.3")).to be_nil
    end
  end
end
