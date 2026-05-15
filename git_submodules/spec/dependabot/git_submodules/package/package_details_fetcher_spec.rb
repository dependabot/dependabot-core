# typed: false
# frozen_string_literal: true

require "json"
require "time"
require "cgi"
require "excon"
require "nokogiri"
require "spec_helper"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/git_submodules"
require "dependabot/package/package_release"
require "dependabot/package/package_details"
require "dependabot/dependency"
require "dependabot/git_submodules/package/package_details_fetcher"

RSpec.describe Dependabot::GitSubmodules::Package::PackageDetailsFetcher do
  subject(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  let(:branch) { "master" }
  let(:details_fetcher_instance) do
    described_class.new(
      dependency: dependency,
      credentials: credentials
    )
  end
  let(:url) { "https://github.com/example/manifesto.git" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "manifesto",
      version: "2468a02a6230e59ed1232d95d1ad3ef157195b03",
      requirements: [{
        file: ".gitmodules",
        requirement: nil,
        groups: [],
        source: { type: "git", url: url, branch: branch, ref: branch }
      }],
      package_manager: "submodules"
    )
  end
  let(:checker) do
    described_class.new(
      dependency: dependency,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
    )
  end

  describe "#latest_version" do
    context "when the response is git based" do
      subject { checker.available_versions }

      let(:git_url) { "https://github.com/example/manifesto.git" }

      before do
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack")
          .to_return(
            status: 200,
            body: fixture("upload_packs", "manifesto"),
            headers: {
              "content-type" => "application/x-git-upload-pack-advertisement"
            }
          )
      end

      it "returns the latest version tag" do
        expect(checker.available_versions.last.tag)
          .to eq("fe1b155799ab728fae7d3edd5451c35942d711c4")
      end
    end

    context "when the repo can't be found" do
      let(:git_url) { "https://github.com/example/manifesto.git" }

      before do
        stub_request(:get, git_url + "/info/refs?service=git-upload-pack")
          .to_return(status: 404)
      end

      it "raises a GitDependenciesNotReachable error" do
        expect { checker.available_versions }.to raise_error do |error|
          expect(error).to be_a(Dependabot::GitDependenciesNotReachable)
          expect(error.dependency_urls)
            .to eq(["https://github.com/example/manifesto.git"])
        end
      end
    end

    describe "#available_versions" do
      it "returns an array of package releases" do
        parsed_results = T.let([], T::Array[Dependabot::GitTagWithDetail])
        parsed_results << Dependabot::GitTagWithDetail.new(
          tag: "95a470a557091cdbdc9f68a178b60bdabncd",
          release_date: "2024-01-01T00:00:00Z"
        )

        allow(checker).to receive_messages(
          build_sha_to_tags: {},
          fetch_tags_and_release_date: parsed_results
        )

        releases = checker.available_versions

        expect(releases.size).to eq(1)
        expect(releases.first.tag).to eq("95a470a557091cdbdc9f68a178b60bdabncd")
        expect(releases.first.released_at).to eq(Time.parse("2024-01-01 00:00:00 UTC"))
      end

      it "fetches latest tag info if no versions metadata is available" do
        allow(checker).to receive_messages(
          build_sha_to_tags: {},
          fetch_tags_and_release_date: []
        )
        allow_any_instance_of(Dependabot::GitCommitChecker).to receive(:head_commit_for_current_branch) # rubocop:disable RSpec/AnyInstance
          .and_return("95a470a557091cdbdc9f68a178b60bd142c")

        releases = checker.available_versions
        expect(releases.size).to eq(1)
        expect(releases.first.tag).to eq("95a470a557091cdbdc9f68a178b60bd142c")
      end

      it "gives priority to tags if available" do
        parsed_results = T.let([], T::Array[Dependabot::GitTagWithDetail])
        parsed_results << Dependabot::GitTagWithDetail.new(
          tag: "95a470a557091cdbdc9f68a178b60bdabncd",
          release_date: "2024-01-01T00:00:00Z"
        )

        allow(checker).to receive_messages(
          build_sha_to_tags: { "95a470a557091cdbdc9f68a178b60bdabncd" => ["v1.0.0"] },
          fetch_tags_and_release_date: parsed_results
        )

        releases = checker.available_versions
        expect(releases.size).to eq(2)
        expect(releases[0].version.semver_parts).to eq([1, 0, 0])
        expect(releases[0].tag).to eq("95a470a557091cdbdc9f68a178b60bdabncd")
        expect(releases[1].version.semver_parts).to eq([0, 0, 0])
        expect(releases[1].tag).to eq("95a470a557091cdbdc9f68a178b60bdabncd")
      end

      it "ignores tags that aren't valid semver" do
        parsed_results = T.let([], T::Array[Dependabot::GitTagWithDetail])
        parsed_results << Dependabot::GitTagWithDetail.new(
          tag: "95a470a557091cdbdc9f68a178b60bdabncd",
          release_date: "2024-01-01T00:00:00Z"
        )

        allow(checker).to receive_messages(
          build_sha_to_tags: { "95a470a557091cdbdc9f68a178b60bdabncd" => ["not-a-version"] },
          fetch_tags_and_release_date: parsed_results
        )

        releases = checker.available_versions
        expect(releases.size).to eq(1)
        expect(releases[0].version.semver_parts).to eq([0, 0, 0])
        expect(releases[0].tag).to eq("95a470a557091cdbdc9f68a178b60bdabncd")
      end

      it "ignores tags that are referring to unknown commits" do
        parsed_results = T.let([], T::Array[Dependabot::GitTagWithDetail])
        parsed_results << Dependabot::GitTagWithDetail.new(
          tag: "95a470a557091cdbdc9f68a178b60bdabncd",
          release_date: "2024-01-01T00:00:00Z"
        )

        allow(checker).to receive_messages(
          build_sha_to_tags: {
            "2468a02a6230e59ed1232d95d1ad3ef157195b03" => ["v2.0.0"],
            "95a470a557091cdbdc9f68a178b60bdabncd" => ["v1.0.0"]
          },
          fetch_tags_and_release_date: parsed_results
        )

        releases = checker.available_versions
        expect(releases.size).to eq(2)
        expect(releases[0].version.semver_parts).to eq([1, 0, 0])
        expect(releases[0].tag).to eq("95a470a557091cdbdc9f68a178b60bdabncd")
        expect(releases[1].version.semver_parts).to eq([0, 0, 0])
        expect(releases[1].tag).to eq("95a470a557091cdbdc9f68a178b60bdabncd")
      end

      it "returns all tags if multiple tags point to the same commit" do
        parsed_results = T.let([], T::Array[Dependabot::GitTagWithDetail])
        parsed_results << Dependabot::GitTagWithDetail.new(
          tag: "95a470a557091cdbdc9f68a178b60bdabncd",
          release_date: "2024-01-01T00:00:00Z"
        )

        allow(checker).to receive_messages(
          build_sha_to_tags: {
            "95a470a557091cdbdc9f68a178b60bdabncd" => ["v2.0.0", "v1.0.0"]
          },
          fetch_tags_and_release_date: parsed_results
        )

        releases = checker.available_versions
        expect(releases.size).to eq(3)
        expect(releases[0].version.semver_parts).to eq([2, 0, 0])
        expect(releases[0].tag).to eq("95a470a557091cdbdc9f68a178b60bdabncd")
        expect(releases[1].version.semver_parts).to eq([1, 0, 0])
        expect(releases[1].tag).to eq("95a470a557091cdbdc9f68a178b60bdabncd")
        expect(releases[2].version.semver_parts).to eq([0, 0, 0])
        expect(releases[2].tag).to eq("95a470a557091cdbdc9f68a178b60bdabncd")
      end

      it "ignores commits before the current one" do
        allow(checker).to receive_messages(
          build_sha_to_tags: {
            "95a470a557091cdbdc9f68a178b60bdabncd" => ["v2.0.0", "v1.0.0"]
          },
          get_commits: [
            {
              sha: "2468a02a6230e59ed1232d95d1ad3ef157195b03",
              commit: { committer: { date: "2024-01-01T00:00:00Z" } }
            },
            {
              sha: "95a470a557091cdbdc9f68a178b60bdabncd",
              commit: { committer: { date: "2024-01-01T00:00:00Z" } }
            }
          ],
          fetch_latest_tag_info: [
            Dependabot::GitTagWithDetail.new(tag: "2468a02a6230e59ed1232d95d1ad3ef157195b03")
          ]
        )

        releases = checker.available_versions
        expect(releases.size).to eq(1)
        expect(releases[0].version.semver_parts).to eq([0, 0, 0])
        expect(releases[0].tag).to eq("2468a02a6230e59ed1232d95d1ad3ef157195b03")
      end
    end
  end
end
