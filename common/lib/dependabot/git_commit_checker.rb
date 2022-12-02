# frozen_string_literal: true

require "excon"
require "gitlab"
require "dependabot/clients/github_with_retries"
require "dependabot/clients/gitlab_with_retries"
require "dependabot/clients/bitbucket_with_retries"
require "dependabot/metadata_finders"
require "dependabot/errors"
require "dependabot/utils"
require "dependabot/source"
require "dependabot/dependency"
require "dependabot/git_metadata_fetcher"
module Dependabot
  class GitCommitChecker
    VERSION_REGEX = /
      (?<version>
        (?<=^v)[0-9]+(?:\-[a-z0-9]+)?
        |
        [0-9]+\.[0-9]+(?:\.[a-z0-9\-]+)*
      )$
    /ix

    def initialize(dependency:, credentials:,
                   ignored_versions: [], raise_on_ignored: false,
                   consider_version_branches_pinned: false)
      @dependency = dependency
      @credentials = credentials
      @ignored_versions = ignored_versions
      @raise_on_ignored = raise_on_ignored
      @consider_version_branches_pinned = consider_version_branches_pinned
    end

    def git_dependency?
      return false if dependency_source_details.nil?

      dependency_source_details.fetch(:type) == "git"
    end

    def pinned?
      raise "Not a git dependency!" unless git_dependency?

      ref = dependency_source_details.fetch(:ref)
      branch = dependency_source_details.fetch(:branch)

      return false if ref.nil?
      return false if branch == ref
      return true if branch
      return true if dependency.version&.start_with?(ref)

      # If the specified `ref` is actually a tag, we're pinned
      return true if local_upload_pack.match?(%r{ refs/tags/#{ref}$})

      # Assume we're pinned unless the specified `ref` is actually a branch
      return true unless local_upload_pack.match?(%r{ refs/heads/#{ref}$})

      # TODO: Research whether considering branches that look like versions pinned makes sense for all ecosystems
      @consider_version_branches_pinned && version_tag?(ref)
    end

    def pinned_ref_looks_like_version?
      return false unless pinned?

      version_tag?(dependency_source_details.fetch(:ref))
    end

    def pinned_ref_looks_like_commit_sha?
      ref = dependency_source_details.fetch(:ref)
      ref_looks_like_commit_sha?(ref)
    end

    def head_commit_for_pinned_ref
      ref = dependency_source_details.fetch(:ref)
      local_repo_git_metadata_fetcher.head_commit_for_ref_sha(ref)
    end

    def ref_looks_like_commit_sha?(ref)
      return false unless ref&.match?(/^[0-9a-f]{6,40}$/)

      return false unless pinned?

      local_repo_git_metadata_fetcher.head_commit_for_ref(ref).nil?
    end

    def branch_or_ref_in_release?(version)
      pinned_ref_in_release?(version) || branch_behind_release?(version)
    end

    def head_commit_for_current_branch
      ref = ref_or_branch || "HEAD"

      sha = head_commit_for_local_branch(ref)
      return sha if pinned? || sha

      raise Dependabot::GitDependencyReferenceNotFound, dependency.name
    end

    def head_commit_for_local_branch(name)
      local_repo_git_metadata_fetcher.head_commit_for_ref(name)
    end

    def local_ref_for_latest_version_matching_existing_precision
      allowed_refs = local_tag_for_pinned_sha ? allowed_version_tags : allowed_version_refs

      max_local_tag_for_current_precision(allowed_refs)
    end

    def local_tag_for_latest_version
      max_local_tag(allowed_version_tags)
    end

    def local_tags_for_allowed_versions_matching_existing_precision
      select_matching_existing_precision(allowed_version_tags).map { |t| to_local_tag(t) }
    end

    def local_tags_for_allowed_versions
      allowed_version_tags.map { |t| to_local_tag(t) }
    end

    def allowed_version_tags
      allowed_versions(local_tags)
    end

    def allowed_version_refs
      allowed_versions(local_refs)
    end

    def current_version
      return unless dependency.version && version_tag?(dependency.version)

      version_from_ref(dependency.version)
    end

    def filter_lower_versions(tags)
      return tags unless current_version

      versions = tags.map do |t|
        version_from_tag(t)
      end

      versions.select do |version|
        version > current_version
      end
    end

    def most_specific_tag_equivalent_to_pinned_ref
      commit_sha = head_commit_for_local_branch(dependency_source_details.fetch(:ref))
      most_specific_version_tag_for_sha(commit_sha)
    end

    def local_tag_for_pinned_sha
      return unless pinned_ref_looks_like_commit_sha?

      commit_sha = dependency_source_details.fetch(:ref)
      most_specific_version_tag_for_sha(commit_sha)
    end

    def git_repo_reachable?
      local_upload_pack
      true
    rescue Dependabot::GitDependenciesNotReachable
      false
    end

    private

    attr_reader :dependency, :credentials, :ignored_versions

    def max_local_tag_for_current_precision(tags)
      max_local_tag(select_matching_existing_precision(tags))
    end

    def max_local_tag(tags)
      max_version_tag = tags.max_by { |t| version_from_tag(t) }

      to_local_tag(max_version_tag)
    end

    # Find the latest version with the same precision as the pinned version.
    def select_matching_existing_precision(tags)
      current_precision = precision(dependency.version)

      tags.select { |tag| precision(scan_version(tag.name)) == current_precision }
    end

    def precision(version)
      version.split(".").length
    end

    def most_specific_version_tag_for_sha(commit_sha)
      tags = local_tags.select { |t| t.commit_sha == commit_sha && version_class.correct?(t.name) }.
             sort_by { |t| version_class.new(t.name) }
      return if tags.empty?

      tags[-1].name
    end

    def allowed_versions(local_tags)
      tags =
        local_tags.
        select { |t| version_tag?(t.name) && matches_existing_prefix?(t.name) }
      filtered = tags.
                 reject { |t| tag_included_in_ignore_requirements?(t) }
      if @raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(tags).any?
        raise Dependabot::AllVersionsIgnored
      end

      filtered.
        reject { |t| tag_is_prerelease?(t) && !wants_prerelease? }
    end

    def pinned_ref_in_release?(version)
      raise "Not a git dependency!" unless git_dependency?

      return false unless pinned?
      return false if listing_source_url.nil?

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

      return false if ref_or_branch.nil?
      return false if listing_source_url.nil?

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

    def local_upload_pack
      local_repo_git_metadata_fetcher.upload_pack
    end

    def local_refs
      handle_tag_prefix(local_repo_git_metadata_fetcher.refs_for_upload_pack)
    end

    def local_tags
      handle_tag_prefix(local_repo_git_metadata_fetcher.tags_for_upload_pack)
    end

    def handle_tag_prefix(tags)
      if dependency_source_details&.fetch(:ref, nil)&.start_with?("tags/")
        tags = tags.map do |tag|
          tag.dup.tap { |t| t.name = "tags/#{tag.name}" }
        end
      end

      tags
    end

    def commit_included_in_tag?(tag:, commit:, allow_identical: false)
      status =
        case Source.from_url(listing_source_url)&.provider
        when "github" then github_commit_comparison_status(tag, commit)
        when "gitlab" then gitlab_commit_comparison_status(tag, commit)
        when "bitbucket" then bitbucket_commit_comparison_status(tag, commit)
        when "codecommit" then nil # TODO: get codecommit comparison status
        else raise "Unknown source"
        end

      return true if status == "behind"

      allow_identical && status == "identical"
    rescue Octokit::NotFound, Gitlab::Error::NotFound,
           Clients::Bitbucket::NotFound,
           Octokit::InternalServerError
      false
    end

    def github_commit_comparison_status(ref1, ref2)
      client = Clients::GithubWithRetries.
               for_github_dot_com(credentials: credentials)

      client.compare(listing_source_repo, ref1, ref2).status
    end

    def gitlab_commit_comparison_status(ref1, ref2)
      client = Clients::GitlabWithRetries.
               for_gitlab_dot_com(credentials: credentials)

      comparison = client.compare(listing_source_repo, ref1, ref2)

      if comparison.commits.none? then "behind"
      elsif comparison.compare_same_ref then "identical"
      else
        "ahead"
      end
    end

    def bitbucket_commit_comparison_status(ref1, ref2)
      url = "https://api.bitbucket.org/2.0/repositories/" \
            "#{listing_source_repo}/commits/?" \
            "include=#{ref2}&exclude=#{ref1}"

      client = Clients::BitbucketWithRetries.
               for_bitbucket_dot_org(credentials: credentials)

      response = client.get(url)

      # Conservatively assume that ref2 is ahead in the equality case, of
      # if we get an unexpected format (e.g., due to a 404)
      if JSON.parse(response.body).fetch("values", ["x"]).none? then "behind"
      else
        "ahead"
      end
    end

    def dependency_source_details
      sources =
        dependency.requirements.
        map { |requirement| requirement.fetch(:source) }.uniq.compact.
        select { |source| source[:type] == "git" }

      return sources.first if sources.count <= 1

      # If there are multiple source types, or multiple source URLs, then it's
      # unclear how we should proceed
      if sources.map { |s| [s.fetch(:type), s.fetch(:url, nil)] }.uniq.count > 1
        raise "Multiple sources! #{sources.join(', ')}"
      end

      # Otherwise it's reasonable to take the first source and use that. This
      # will happen if we have multiple git sources with difference references
      # specified. In that case it's fine to update them all.
      sources.first
    end

    def ref_or_branch
      dependency_source_details.fetch(:ref) ||
        dependency_source_details.fetch(:branch)
    end

    def version_tag?(tag)
      tag.match?(VERSION_REGEX)
    end

    def matches_existing_prefix?(tag)
      return true unless ref_or_branch&.match?(VERSION_REGEX)

      ref_or_branch.gsub(VERSION_REGEX, "").gsub(/v$/i, "") ==
        tag.gsub(VERSION_REGEX, "").gsub(/v$/i, "")
    end

    def to_local_tag(tag)
      return unless tag

      version = version_from_tag(tag)
      {
        tag: tag.name,
        version: version,
        commit_sha: tag.commit_sha,
        tag_sha: tag.ref_sha
      }
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
            new(dependency: candidate_dep, credentials: credentials).
            source_url
        end
    end

    def listing_source_repo
      return unless listing_source_url

      Source.from_url(listing_source_url)&.repo
    end

    def listing_tag_for_version(version)
      listing_tags.
        find { |t| t.name =~ /(?:[^0-9\.]|\A)#{Regexp.escape(version)}\z/ }&.
        name
    end

    def listing_tags
      return [] unless listing_source_url

      @listing_tags ||= begin
        tags = listing_repo_git_metadata_fetcher.tags

        if dependency_source_details&.fetch(:ref, nil)&.start_with?("tags/")
          tags = tags.map do |tag|
            tag.dup.tap { |t| t.name = "tags/#{tag.name}" }
          end
        end

        tags
      rescue GitDependenciesNotReachable
        []
      end
    end

    def listing_upload_pack
      return unless listing_source_url

      listing_repo_git_metadata_fetcher.upload_pack
    end

    def ignore_requirements
      ignored_versions.flat_map { |req| requirement_class.requirements_array(req) }
    end

    def wants_prerelease?
      return false unless dependency_source_details&.fetch(:ref, nil)
      return false unless pinned_ref_looks_like_version?

      version = version_from_ref(dependency_source_details.fetch(:ref))
      version.prerelease?
    end

    def tag_included_in_ignore_requirements?(tag)
      version = version_from_tag(tag)
      ignore_requirements.any? { |r| r.satisfied_by?(version) }
    end

    def tag_is_prerelease?(tag)
      version_from_tag(tag).prerelease?
    end

    def version_from_tag(tag)
      version_from_ref(tag.name)
    end

    def version_from_ref(name)
      version_class.new(scan_version(name))
    end

    def scan_version(name)
      name.match(VERSION_REGEX).named_captures.fetch("version")
    end

    def version_class
      @version_class ||= Utils.version_class_for_package_manager(dependency.package_manager)
    end

    def requirement_class
      @requirement_class ||= Utils.requirement_class_for_package_manager(dependency.package_manager)
    end

    def local_repo_git_metadata_fetcher
      @local_repo_git_metadata_fetcher ||=
        GitMetadataFetcher.new(
          url: dependency_source_details.fetch(:url),
          credentials: credentials
        )
    end

    def listing_repo_git_metadata_fetcher
      @listing_repo_git_metadata_fetcher ||=
        GitMetadataFetcher.new(
          url: listing_source_url,
          credentials: credentials
        )
    end
  end
end
