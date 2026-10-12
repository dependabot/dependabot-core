# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/clients/github_release"
require "dependabot/clients/github_with_retries"
require "dependabot/shared_helpers"
require "dependabot/source"

module Dependabot
  # Shared logic for resolving release dates from git-based sources for cooldown
  # purposes. Used by ecosystems that rely on git tags (pre-commit, GitHub Actions)
  # rather than package registries.
  #
  # Priority: GitHub Release published_at > tag creation date (for-each-ref) > commit date.
  #
  # Including classes must implement:
  #   - `cooldown_source_url` — returns the git source URL
  #   - `cooldown_credentials` — returns the credentials array
  module GitCooldownDateResolver
    extend T::Sig
    extend T::Helpers

    abstract!

    # The git source URL for the dependency (e.g. "https://github.com/owner/repo")
    sig { abstract.returns(T.nilable(String)) }
    def cooldown_source_url; end

    # Credentials for GitHub API access
    sig { abstract.returns(T::Array[Dependabot::Credential]) }
    def cooldown_credentials; end

    # Strips the `tags/` prefix that GitCommitChecker may add when the pinned
    # ref starts with `tags/`, preventing construction of invalid refs like
    # `refs/tags/tags/v1.0.0`.
    sig { params(tag_name: String).returns(String) }
    def normalize_tag_name(tag_name)
      tag_name.delete_prefix("tags/")
    end

    # Resolves the best available date for a candidate tag.
    # Priority: GitHub Release published_at > tag creation date > commit date.
    sig { params(tag_name: String, commit_sha: String).returns(Time) }
    def resolve_candidate_date(tag_name, commit_sha)
      releases = cached_github_releases
      unless releases.empty?
        release = releases.find { |r| r.tag_name == tag_name }
        published_at = release&.published_at
        return published_at if published_at
      end

      tag_creation_date(tag_name, commit_sha)
    end

    # Looks up the GitHub Release published_at date for a given tag name.
    # Returns nil if no release exists for this tag.
    sig { params(tag_name: String).returns(T.nilable(Time)) }
    def github_release_published_at(tag_name)
      releases = cached_github_releases
      return nil if releases.empty?

      release = releases.find { |r| r.tag_name == tag_name }
      return nil unless release&.published_at

      release.published_at
    rescue StandardError => e
      Dependabot.logger.debug("Error fetching GitHub release date for #{tag_name}: #{e.message}")
      nil
    end

    # Returns the tag creation date for cooldown purposes (used inside bare clone).
    # Priority: tag creation date from for-each-ref > commit date fallback.
    sig { params(tag_name: String, commit_sha: String).returns(Time) }
    def tag_creation_date(tag_name, commit_sha)
      tag_date_str = SharedHelpers.run_shell_command(
        "git for-each-ref --format=\"%(creatordate:iso)\" \"refs/tags/#{tag_name}\"",
        fingerprint: "git for-each-ref --format=\"%(creatordate:iso)\" \"refs/tags/<tag_name>\""
      ).strip

      if tag_date_str.empty?
        tag_date_str = SharedHelpers.run_shell_command(
          "git show --no-patch --format=\"%cd\" --date=iso #{commit_sha}",
          fingerprint: "git show --no-patch --format=\"%cd\" --date=iso <commit_sha>"
        ).strip
      end

      Time.parse(tag_date_str)
    end

    # Fetches and caches GitHub releases for the dependency source.
    # Returns an empty array for non-GitHub sources.
    sig { returns(T::Array[Dependabot::Clients::GithubRelease]) }
    def cached_github_releases
      @cached_github_releases ||= T.let(
        begin
          url = cooldown_source_url
          source = Source.from_url(url)
          if source&.provider == "github"
            client = Dependabot::Clients::GithubWithRetries.for_source(
              source: T.must(source),
              credentials: cooldown_credentials
            )
            releases = T.let(
              client.releases(T.must(source).repo, per_page: 100),
              T.nilable(T::Array[Sawyer::Resource])
            )
            (releases || []).filter_map do |release|
              Dependabot::Clients::GithubRelease.from_resource(release)
            end
          else
            []
          end
        rescue StandardError => e
          Dependabot.logger.debug("Error fetching GitHub releases: #{e.message}")
          []
        end,
        T.nilable(T::Array[Dependabot::Clients::GithubRelease])
      )
    end
  end
end
