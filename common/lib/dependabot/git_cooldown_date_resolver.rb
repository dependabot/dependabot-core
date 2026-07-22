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
  # For GitHub sources, a lightweight tag with no non-draft published release is
  # treated conservatively (as still in cooldown) because its for-each-ref date
  # reflects the underlying commit date, not when the tag was actually created.
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
    #
    # Priority:
    # 1. GitHub Release published_at (non-draft only)
    # 2. For GitHub sources with no non-draft release: conservative fallback for
    #    lightweight tags — returns Time.now so the version stays in cooldown.
    # 3. Tag creation date (for-each-ref creatordate) for annotated tags.
    # 4. Commit date (git show %cd) as last resort.
    #
    # The conservative fallback (step 2) prevents freshly-pushed lightweight tags
    # from bypassing cooldown when no published release exists, because
    # %(creatordate) for a lightweight tag returns the underlying commit date
    # rather than when the tag was actually created.
    sig { params(tag_name: String, commit_sha: String).returns(Time) }
    def resolve_candidate_date(tag_name, commit_sha)
      releases = cached_github_releases

      unless releases.empty?
        release = releases.find { |r| r.tag_name == tag_name && !r.draft }
        if release
          published_at = release.published_at
          return published_at if published_at
        end
      end

      # For GitHub sources: be conservative for lightweight tags with no
      # trustworthy release date. A lightweight tag's %(creatordate) is the
      # commit date (potentially much older than when the tag was pushed),
      # which would incorrectly bypass cooldown for freshly-tagged versions.
      if github_source? && lightweight_tag?(tag_name)
        Dependabot.logger.info(
          "Tag #{tag_name} is a lightweight tag with no published GitHub Release; " \
          "treating version as still in cooldown to avoid bypassing cooldown window."
        )
        return Time.now
      end

      tag_creation_date(tag_name, commit_sha)
    end

    # Looks up the GitHub Release published_at date for a given tag name.
    # Draft releases are excluded because they are not publicly available.
    # Returns nil if no non-draft release exists for this tag.
    sig { params(tag_name: String).returns(T.nilable(Time)) }
    def github_release_published_at(tag_name)
      releases = cached_github_releases
      return nil if releases.empty?

      release = releases.find { |r| r.tag_name == tag_name && !r.draft }
      release&.published_at
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

    private

    # Returns true if the dependency source is hosted on GitHub.
    sig { returns(T::Boolean) }
    def github_source?
      url = cooldown_source_url
      return false unless url

      source = Source.from_url(url)
      return false unless source

      source.provider == "github"
    end

    # Returns true if the given tag is a lightweight tag (points directly to a
    # commit rather than a tag object). For lightweight tags, %(creatordate)
    # returns the committer date of the pointed-to commit, not when the tag was
    # created — making it unsuitable as a proxy for release time.
    #
    # Returns false on error or when the tag is not found, so that we fail open
    # (allow the existing tag_creation_date fallback) rather than permanently
    # blocking a dependency.
    sig { params(tag_name: String).returns(T::Boolean) }
    def lightweight_tag?(tag_name)
      object_type = SharedHelpers.run_shell_command(
        "git for-each-ref --format=\"%(objecttype)\" \"refs/tags/#{tag_name}\"",
        fingerprint: "git for-each-ref --format=\"%(objecttype)\" \"refs/tags/<tag_name>\""
      ).strip

      # "tag" = annotated tag object with its own creation date
      # "commit" = lightweight tag pointing directly at a commit
      # "" = tag not found in this clone
      object_type == "commit"
    rescue StandardError => e
      Dependabot.logger.debug("Unable to determine tag type for #{tag_name}: #{e.message}")
      false
    end
  end
end
