# typed: false
# frozen_string_literal: true

require "spec_helper"
require "json"
require "dependabot/dependency"
require "dependabot/nix/package/package_details_fetcher"

RSpec.describe Dependabot::Nix::Package::PackageDetailsFetcher do
  let(:current_sha) { "6201e203d09599479a3b3450ed24fa81537ebc4e" }
  let(:url) { "https://github.com/NixOS/nixpkgs" }
  let(:ref) { "nixos-unstable" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "nixpkgs",
      version: current_sha,
      requirements: [{
        file: "flake.lock",
        requirement: nil,
        groups: [],
        source: { type: "git", url: url, branch: nil, ref: ref }
      }],
      package_manager: "nix"
    )
  end
  let(:credentials) do
    [{ "type" => "git_source", "host" => "github.com", "username" => "x-access-token", "password" => "test-token" }]
  end
  let(:fetcher) { described_class.new(dependency: dependency, credentials: credentials) }

  let(:activity_url) do
    "https://api.github.com/repos/NixOS/nixpkgs/activity" \
      "?activity_type=push,force_push&per_page=100&ref=refs/heads/nixos-unstable"
  end
  let(:activity_response) do
    [
      { "id" => 1, "before" => "b12141ef619e", "after" => "0726a0ec",
        "ref" => "refs/heads/nixos-unstable", "timestamp" => "2026-04-24T20:30:00Z", "activity_type" => "push" },
      { "id" => 2, "before" => "4bd9165a9165", "after" => "b12141ef",
        "ref" => "refs/heads/nixos-unstable", "timestamp" => "2026-04-20T19:04:11Z", "activity_type" => "push" },
      { "id" => 3, "before" => current_sha, "after" => "4bd9165a",
        "ref" => "refs/heads/nixos-unstable", "timestamp" => "2026-04-15T18:15:58Z", "activity_type" => "push" }
    ]
  end

  describe "#available_versions" do
    context "when activity API returns data" do
      before do
        stub_request(:get, activity_url).to_return(
          status: 200,
          body: activity_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "returns releases derived from branch-tip pushes" do
        versions = fetcher.available_versions
        expect(versions.map(&:tag)).to eq(%w(0726a0ec b12141ef 4bd9165a))
        expect(versions.map(&:released_at)).to eq(
          [
            Time.parse("2026-04-24T20:30:00Z"),
            Time.parse("2026-04-20T19:04:11Z"),
            Time.parse("2026-04-15T18:15:58Z")
          ]
        )
      end

      it "assigns descending pseudo-versions" do
        versions = fetcher.available_versions
        expect(versions.map(&:version)).to eq(
          [
            Dependabot::Nix::Version.new("0.0.0-0.3"),
            Dependabot::Nix::Version.new("0.0.0-0.2"),
            Dependabot::Nix::Version.new("0.0.0-0.1")
          ]
        )
      end

      it "sends an Authorization header derived from credentials" do
        fetcher.available_versions
        expect(WebMock).to have_requested(:get, activity_url)
          .with(headers: { "Authorization" => "token test-token" })
      end
    end

    context "when activity API returns 403" do
      before do
        stub_request(:get, activity_url).to_return(
          status: 403,
          body: '{"message":"rate limited"}',
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "falls back to the commits-based fetcher" do
        # Stub the GitCommitChecker to short-circuit the fallback path
        git_checker = instance_double(Dependabot::GitCommitChecker)
        allow(Dependabot::GitCommitChecker).to receive(:new).and_return(git_checker)
        allow(git_checker).to receive_messages(
          ref_details_for_pinned_ref: instance_double(
            Excon::Response,
            status: 200,
            body: "[]"
          ),
          head_commit_for_current_branch: "fallback_sha"
        )

        versions = fetcher.available_versions
        expect(versions.map(&:tag)).to eq(["fallback_sha"])
      end
    end

    context "when activity API returns an empty array" do
      before do
        stub_request(:get, activity_url).to_return(
          status: 200,
          body: "[]",
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "falls back to the commits-based fetcher" do
        git_checker = instance_double(Dependabot::GitCommitChecker)
        allow(Dependabot::GitCommitChecker).to receive(:new).and_return(git_checker)
        allow(git_checker).to receive_messages(
          ref_details_for_pinned_ref: instance_double(
            Excon::Response,
            status: 200,
            body: "[]"
          ),
          head_commit_for_current_branch: "fallback_sha"
        )

        fetcher.available_versions
        expect(WebMock).to have_requested(:get, activity_url)
      end
    end

    context "when the ref is a 40-char SHA" do
      let(:ref) { "0123456789abcdef0123456789abcdef01234567" }

      it "skips the activity API and uses the commits walker" do
        git_checker = instance_double(Dependabot::GitCommitChecker)
        allow(Dependabot::GitCommitChecker).to receive(:new).and_return(git_checker)
        allow(git_checker).to receive_messages(
          ref_details_for_pinned_ref: instance_double(
            Excon::Response,
            status: 200,
            body: "[]"
          ),
          head_commit_for_current_branch: "fallback_sha"
        )

        fetcher.available_versions
        expect(WebMock).not_to have_requested(:get, /api\.github\.com/)
      end
    end

    context "when the source URL is not on github.com" do
      let(:url) { "https://gitlab.com/foo/bar" }

      it "skips the activity API and uses the commits walker" do
        git_checker = instance_double(Dependabot::GitCommitChecker)
        allow(Dependabot::GitCommitChecker).to receive(:new).and_return(git_checker)
        allow(git_checker).to receive_messages(
          ref_details_for_pinned_ref: instance_double(
            Excon::Response,
            status: 200,
            body: "[]"
          ),
          head_commit_for_current_branch: "fallback_sha"
        )

        fetcher.available_versions
        expect(WebMock).not_to have_requested(:get, /api\.github\.com/)
      end
    end

    context "when no github.com credential is present" do
      let(:credentials) { [] }

      before do
        stub_request(:get, activity_url).to_return(
          status: 200,
          body: activity_response.to_json,
          headers: { "Content-Type" => "application/json" }
        )
      end

      it "still calls the activity API without an Authorization header" do
        fetcher.available_versions
        expect(WebMock).to(
          have_requested(:get, activity_url)
                    .with { |req| !req.headers.key?("Authorization") }
        )
      end
    end
  end
end
