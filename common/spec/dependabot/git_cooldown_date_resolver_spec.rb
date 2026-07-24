# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/git_cooldown_date_resolver"
require "dependabot/shared_helpers"
require "dependabot/clients/github_with_retries"

RSpec.describe Dependabot::GitCooldownDateResolver do
  let(:test_class) do
    Class.new do
      include Dependabot::GitCooldownDateResolver

      def initialize(source_url:, credentials:)
        @source_url = source_url
        @credentials = credentials
      end

      def cooldown_source_url
        @source_url
      end

      def cooldown_credentials
        @credentials
      end
    end
  end

  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }
    )]
  end

  let(:source_url) { "https://github.com/owner/repo" }
  let(:resolver) { test_class.new(source_url: source_url, credentials: credentials) }
  let(:sawyer_agent) { instance_double(Sawyer::Agent) }

  before do
    allow(sawyer_agent).to receive(:parse_links) { |value| [value, {}] }
  end

  def github_release_resource(agent, tag_name:, published_at:)
    Sawyer::Resource.new(
      agent,
      { tag_name: tag_name, published_at: published_at, prerelease: false }
    )
  end

  describe "#normalize_tag_name" do
    it "strips tags/ prefix" do
      expect(resolver.normalize_tag_name("tags/v1.0.0")).to eq("v1.0.0")
    end

    it "leaves normal tag names unchanged" do
      expect(resolver.normalize_tag_name("v1.0.0")).to eq("v1.0.0")
    end

    it "only strips the first tags/ prefix" do
      expect(resolver.normalize_tag_name("tags/tags/v1.0.0")).to eq("tags/v1.0.0")
    end
  end

  describe "#tag_creation_date" do
    it "returns the tag creation date from git for-each-ref" do
      tag_date = "2026-06-10 12:00:00 +0000"
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(/git for-each-ref/, hash_including(fingerprint: anything))
        .and_return(tag_date)

      result = resolver.tag_creation_date("v1.0.0", "abc123")
      expect(result).to eq(Time.parse(tag_date))
    end

    it "falls back to commit date when for-each-ref returns empty" do
      commit_date = "2026-06-08 10:00:00 +0000"
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(/git for-each-ref/, hash_including(fingerprint: anything))
        .and_return("")
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(/git show --no-patch/, hash_including(fingerprint: anything))
        .and_return(commit_date)

      result = resolver.tag_creation_date("v1.0.0", "abc123")
      expect(result).to eq(Time.parse(commit_date))
    end
  end

  describe "#github_release_published_at" do
    it "returns published_at when a matching release exists" do
      published_at = Time.now.utc - (3 * 24 * 60 * 60)
      mock_release = github_release_resource(sawyer_agent, tag_name: "v1.0.0", published_at: published_at)
      mock_client = instance_double(Octokit::Client, releases: [mock_release])
      allow(Dependabot::Clients::GithubWithRetries).to receive(:for_source).and_return(mock_client)

      expect(resolver.github_release_published_at("v1.0.0")).to eq(published_at)
    end

    it "returns nil when no release matches the tag" do
      mock_release = github_release_resource(sawyer_agent, tag_name: "v2.0.0", published_at: Time.now)
      mock_client = instance_double(Octokit::Client, releases: [mock_release])
      allow(Dependabot::Clients::GithubWithRetries).to receive(:for_source).and_return(mock_client)

      expect(resolver.github_release_published_at("v1.0.0")).to be_nil
    end

    it "returns nil when releases are empty" do
      mock_client = instance_double(Octokit::Client, releases: [])
      allow(Dependabot::Clients::GithubWithRetries).to receive(:for_source).and_return(mock_client)

      expect(resolver.github_release_published_at("v1.0.0")).to be_nil
    end
  end

  describe "#resolve_candidate_date" do
    it "prefers GitHub Release published_at over git dates" do
      published_at = Time.now.utc - (2 * 24 * 60 * 60)
      mock_release = github_release_resource(sawyer_agent, tag_name: "v1.0.0", published_at: published_at)
      mock_client = instance_double(Octokit::Client, releases: [mock_release])
      allow(Dependabot::Clients::GithubWithRetries).to receive(:for_source).and_return(mock_client)

      # Should NOT call git commands
      expect(Dependabot::SharedHelpers).not_to receive(:run_shell_command)

      result = resolver.resolve_candidate_date("v1.0.0", "abc123")
      expect(result).to eq(published_at)
    end

    it "falls back to tag_creation_date when no release exists" do
      mock_client = instance_double(Octokit::Client, releases: [])
      allow(Dependabot::Clients::GithubWithRetries).to receive(:for_source).and_return(mock_client)

      tag_date = "2026-06-10 12:00:00 +0000"
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
        .with(/git for-each-ref/, hash_including(fingerprint: anything))
        .and_return(tag_date)

      result = resolver.resolve_candidate_date("v1.0.0", "abc123")
      expect(result).to eq(Time.parse(tag_date))
    end
  end

  describe "#cached_github_releases" do
    it "fetches releases from GitHub" do
      published_at = Time.now
      mock_release = github_release_resource(sawyer_agent, tag_name: "v1.0.0", published_at: published_at)
      mock_client = instance_double(Octokit::Client, releases: [mock_release])
      allow(Dependabot::Clients::GithubWithRetries).to receive(:for_source).and_return(mock_client)

      result = resolver.cached_github_releases
      expect(result).to contain_exactly(
        have_attributes(tag_name: "v1.0.0", published_at: published_at)
      )
    end

    it "returns an empty array for a nil releases response" do
      mock_client = instance_double(Octokit::Client, releases: nil)
      allow(Dependabot::Clients::GithubWithRetries).to receive(:for_source).and_return(mock_client)

      expect(resolver.cached_github_releases).to eq([])
    end

    it "returns empty array for non-GitHub sources" do
      non_github_resolver = test_class.new(
        source_url: "https://gitlab.com/owner/repo",
        credentials: credentials
      )

      result = non_github_resolver.cached_github_releases
      expect(result).to eq([])
    end

    it "caches the result across multiple calls" do
      mock_client = instance_double(Octokit::Client, releases: [])
      allow(Dependabot::Clients::GithubWithRetries).to receive(:for_source).and_return(mock_client)

      resolver.cached_github_releases
      resolver.cached_github_releases

      expect(Dependabot::Clients::GithubWithRetries).to have_received(:for_source).once
    end

    it "caches empty results (non-GitHub sources)" do
      non_github_resolver = test_class.new(
        source_url: "https://gitlab.com/owner/repo",
        credentials: credentials
      )
      allow(Dependabot::Clients::GithubWithRetries).to receive(:for_source)

      non_github_resolver.cached_github_releases
      non_github_resolver.cached_github_releases

      # Should never try to create a client for non-GitHub sources
      expect(Dependabot::Clients::GithubWithRetries).not_to have_received(:for_source)
    end

    it "returns empty array and caches on API error" do
      allow(Dependabot::Clients::GithubWithRetries).to receive(:for_source)
        .and_raise(StandardError.new("API rate limit"))

      result = resolver.cached_github_releases
      expect(result).to eq([])

      # Second call should not hit the API again
      result2 = resolver.cached_github_releases
      expect(result2).to eq([])
      expect(Dependabot::Clients::GithubWithRetries).to have_received(:for_source).once
    end
  end
end
