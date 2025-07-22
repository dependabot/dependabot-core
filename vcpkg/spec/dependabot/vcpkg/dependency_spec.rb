# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/vcpkg/dependency"

RSpec.describe Dependabot::Vcpkg::Dependency do
  let(:dependency) do
    described_class.new(
      name: "github.com/microsoft/vcpkg",
      version: version,
      previous_version: previous_version,
      requirements: requirements,
      package_manager: "vcpkg"
    )
  end

  let(:version) { "abc123def456789012345678901234567890abcd" }
  let(:previous_version) { "def789abc123456789012345678901234567890def" }
  let(:requirements) do
    [{
      requirement: nil,
      groups: [],
      source: {
        type: "git",
        url: "https://github.com/microsoft/vcpkg.git",
        ref: version
      },
      file: "vcpkg.json"
    }]
  end

  let(:git_commit_checker) { instance_double(Dependabot::GitCommitChecker) }
  let(:mock_tags) { [] }

  before do
    allow(Dependabot::GitCommitChecker).to receive(:new)
      .with(dependency: dependency, credentials: [])
      .and_return(git_commit_checker)
    allow(git_commit_checker).to receive(:local_tags_for_allowed_versions)
      .and_return(mock_tags)
  end

  describe "#humanized_version" do
    context "when version is not a 40-character SHA" do
      let(:version) { "1.2.3" }

      it "delegates to parent class" do
        expect(dependency.humanized_version).to eq("1.2.3")
      end
    end

    context "when version is a 40-character SHA" do
      context "with a matching git tag" do
        let(:mock_tags) do
          [{
            tag: "2025.06.13",
            commit_sha: version,
            tag_sha: "def456789012345678901234567890abcdef123"
          }]
        end

        it "returns the tag name" do
          expect(dependency.humanized_version).to eq("2025.06.13")
        end
      end

      context "with a matching tag SHA" do
        let(:mock_tags) do
          [{
            tag: "2025.06.13",
            commit_sha: "def456789012345678901234567890abcdef123",
            tag_sha: version
          }]
        end

        it "returns the tag name" do
          expect(dependency.humanized_version).to eq("2025.06.13")
        end
      end

      context "with no matching tag" do
        let(:mock_tags) do
          [{
            tag: "2025.06.13",
            commit_sha: "different_sha_123456789012345678901234567890",
            tag_sha: "another_sha_456789012345678901234567890123"
          }]
        end

        it "returns first 6 characters of SHA with backticks" do
          expect(dependency.humanized_version).to eq("`abc123d`")
        end
      end

      context "when git repository is not reachable" do
        before do
          allow(git_commit_checker).to receive(:local_tags_for_allowed_versions)
            .and_raise(Dependabot::GitDependenciesNotReachable.new(["https://github.com/microsoft/vcpkg.git"]))
        end

        it "returns first 6 characters of SHA with backticks" do
          expect(dependency.humanized_version).to eq("`abc123d`")
        end
      end
    end

    context "when dependency has no git source" do
      let(:requirements) do
        [{
          requirement: nil,
          groups: [],
          source: nil,
          file: "vcpkg.json"
        }]
      end

      it "returns first 6 characters of SHA with backticks" do
        expect(dependency.humanized_version).to eq("`abc123d`")
      end
    end
  end

  describe "#humanized_previous_version" do
    context "when previous_version is not a 40-character SHA" do
      let(:previous_version) { "1.2.2" }

      it "delegates to parent class" do
        expect(dependency.humanized_previous_version).to eq("1.2.2")
      end
    end

    context "when previous_version is a 40-character SHA" do
      context "with a matching git tag" do
        let(:mock_tags) do
          [{
            tag: "2025.04.09",
            commit_sha: previous_version,
            tag_sha: "def456789012345678901234567890abcdef123"
          }]
        end

        it "returns the tag name" do
          expect(dependency.humanized_previous_version).to eq("2025.04.09")
        end
      end

      context "with no matching tag" do
        let(:mock_tags) do
          [{
            tag: "2025.06.13",
            commit_sha: "different_sha_123456789012345678901234567890",
            tag_sha: "another_sha_456789012345678901234567890123"
          }]
        end

        it "returns first 6 characters of SHA with backticks" do
          expect(dependency.humanized_previous_version).to eq("`def789a`")
        end
      end
    end

    context "when previous_version is nil" do
      let(:previous_version) { nil }

      it "delegates to parent class" do
        expect(dependency.humanized_previous_version).to be_nil
      end
    end
  end

  describe "caching behavior" do
    let(:mock_tags) do
      [{
        tag: "2025.06.13",
        commit_sha: version,
        tag_sha: "def456789012345678901234567890abcdef123"
      }]
    end

    it "caches tag lookup results" do
      # First call should fetch from git
      expect(dependency.humanized_version).to eq("2025.06.13")

      # Second call should use cached result
      expect(dependency.humanized_version).to eq("2025.06.13")

      # Should only have called git_commit_checker once
      expect(git_commit_checker).to have_received(:local_tags_for_allowed_versions).once
    end
  end
end
