# frozen_string_literal: true

require "octokit"
require "excon"
require "dependabot/metadata_finders"

module Dependabot
  class GitCommitChecker
    VERSION_REGEX = /(?<version>[0-9]+\.[0-9]+(?:\.[a-zA-Z0-9]+)*)$/

    def initialize(dependency:, github_access_token:)
      @dependency = dependency
      @github_access_token = github_access_token
    end

    def git_dependency?
      return false if dependency_source_details.nil?

      dependency_source_details.fetch(:type) == "git"
    end

    # rubocop:disable Metrics/CyclomaticComplexity
    def pinned?
      raise "Not a git dependency!" unless git_dependency?

      source_ref = dependency_source_details.fetch(:ref)

      # If there's no reference specified, we can't be pinned
      return false if source_ref.nil?

      # If the branch specified matches the ref, the ref must be a branch
      return false if dependency_source_details.fetch(:branch) == source_ref

      # If there's a branch specified, and it doesn't match the ref specified,
      # then the ref can't be a branch so must be a commit.
      # Example: `version: a1b312c, branch: master, ref: v1.0.0
      return true if dependency_source_details.fetch(:branch)

      # If the ref specified matches the current version, it must be a commit
      return true if dependency.version&.start_with?(source_ref)

      # At this point we know we've got a reference specified and no branch.
      # It's unlikely, but that reference could be a branch (e.g., if specified
      # as `ref:  "master"` in the Gemfile). Check by hitting the URL.
      @upload_pack_response ||=
        fetch_upload_pack_for(dependency_source_details.fetch(:url))

      return false unless @upload_pack_response.status == 200

      !@upload_pack_response.body.match?("refs/heads/#{source_ref}")
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    def branch_or_ref_in_release?(version)
      pinned_ref_in_release?(version) || branch_behind_release?(version)
    end

    def pinned_ref_looks_like_version?
      return false unless pinned?
      dependency_source_details.fetch(:ref).match?(VERSION_REGEX)
    end

    def local_tag_for_version(version)
      tag =
        local_tags.
        find { |t| t.name =~ /(?:[^0-9\.]|\A)#{Regexp.escape(version.to_s)}\z/ }

      return unless tag
      { tag: tag.name, commit_sha: tag.commit.sha }
    end

    def local_tag_for_latest_version
      tag =
        local_tags.
        select { |t| t.name.match?(VERSION_REGEX) }.
        max_by do |t|
          version = t.name.match(VERSION_REGEX).named_captures.fetch("version")
          Gem::Version.new(version)
        end

      return unless tag
      { tag: tag.name, commit_sha: tag.commit.sha }
    end

    private

    attr_reader :dependency, :github_access_token

    def pinned_ref_in_release?(version)
      raise "Not a git dependency!" unless git_dependency?

      return false unless pinned?
      return false if listing_source_url.nil?
      return false unless listing_source_hosted_on_github?

      tag = listing_tag_for_version(version.to_s)
      return false unless tag

      commit_included_in_tag?(
        commit: dependency_source_details.fetch(:ref),
        tag: tag,
        allow_identical: true
      )
    end

    def branch_behind_release?(version)
      raise "Not a git dependency!" unless git_dependency?

      return false if listing_source_url.nil?
      return false unless listing_source_hosted_on_github?

      tag = listing_tag_for_version(version.to_s)
      return false unless tag

      # Check if behind, excluding the case where it's identical, because
      # we normally wouldn't switch you from tracking master to a release.
      commit_included_in_tag?(
        commit: ref_or_branch,
        tag: tag,
        allow_identical: false
      )
    end

    def fetch_upload_pack_for(uri)
      uri = uri.gsub(
        "git@github.com:",
        "https://x-access-token:#{github_access_token}/"
      )
      uri = uri.gsub(%r{/$}, "")
      uri += ".git" unless uri.end_with?(".git")
      uri += "/info/refs?service=git-upload-pack"

      Excon.get(
        uri,
        idempotent: true,
        middlewares: SharedHelpers.excon_middleware
      )
    end

    def commit_included_in_tag?(tag:, commit:, allow_identical: false)
      status =
        github_client.compare(
          listing_source_repo,
          tag,
          commit
        ).status
      return true if status == "behind"
      allow_identical && status == "identical"
    rescue Octokit::NotFound
      false
    end

    def dependency_source_details
      sources =
        dependency.requirements.map { |r| r.fetch(:source) }.uniq.compact

      raise "Multiple sources! #{sources.join(', ')}" if sources.count > 1

      sources.first
    end

    def ref_or_branch
      dependency_source_details.fetch(:ref) ||
        dependency_source_details.fetch(:branch)
    end

    def listing_source_url
      @listing_source_url ||=
        begin
          # Remove the git source, so the metadata finder looks on the
          # registry
          candidate_dep = Dependency.new(
            name: dependency.name,
            version: dependency.version,
            requirements: [],
            package_manager: dependency.package_manager
          )

          MetadataFinders.
            for_package_manager(dependency.package_manager).
            new(
              dependency: candidate_dep,
              github_client: github_client
            ).
            source_url
        end
    end

    def listing_source_hosted_on_github?
      listing_source_url.start_with?(github_client.web_endpoint)
    end

    def listing_source_repo
      listing_source_url.gsub(github_client.web_endpoint, "")
    end

    def listing_tag_for_version(version)
      listing_tags.
        find { |t| t.name =~ /(?:[^0-9\.]|\A)#{Regexp.escape(version)}\z/ }&.
        name
    end

    def listing_tags
      @listing_tags ||= github_client.tags(listing_source_repo, per_page: 100)
    end

    def local_source_url
      @local_source_url ||=
        MetadataFinders.
        for_package_manager(dependency.package_manager).
        new(dependency: dependency, github_client: github_client).
        source_url
    end

    def local_source_hosted_on_github?
      local_source_url.start_with?(github_client.web_endpoint)
    end

    def local_source_repo
      local_source_url.gsub(github_client.web_endpoint, "")
    end

    def local_tags
      return [] unless local_source_url
      return [] unless local_source_hosted_on_github?
      @local_tags ||= github_client.tags(local_source_repo, per_page: 100)
    end

    def github_client
      @github_client ||=
        Octokit::Client.new(access_token: github_access_token)
    end
  end
end
