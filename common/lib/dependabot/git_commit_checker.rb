# typed: strict
# frozen_string_literal: true

require "excon"
require "gitlab"
require "sorbet-runtime"
require "dependabot/clients/github_with_retries"
require "dependabot/clients/gitlab_with_retries"
require "dependabot/clients/bitbucket_with_retries"
require "dependabot/metadata_finders"
require "dependabot/errors"
require "dependabot/utils"
require "dependabot/source"
require "dependabot/dependency"
require "dependabot/credential"
require "dependabot/git_metadata_fetcher"
module Dependabot
  # rubocop:disable Metrics/ClassLength
  class GitCommitChecker
    extend T::Sig

    VERSION_REGEX = /
      (?<version>
        (?<=^v)[0-9]+(?:\-[a-z0-9]+)?
        |
        [0-9]+\.[0-9]+(?:\.[a-z0-9\-]+)*
      )$
    /ix

    sig do
      params(
        dependency: Dependabot::Dependency,
        credentials: T::Array[Dependabot::Credential],
        ignored_versions: T::Array[String],
        raise_on_ignored: T::Boolean,
        consider_version_branches_pinned: T::Boolean,
        dependency_source_details: T.nilable(T::Hash[Symbol, String])
      )
        .void
    end
    def initialize(dependency:, credentials:,
                   ignored_versions: [], raise_on_ignored: false,
                   consider_version_branches_pinned: false, dependency_source_details: nil)
      @dependency = dependency
      @credentials = credentials
      @ignored_versions = ignored_versions
      @raise_on_ignored = raise_on_ignored
      @consider_version_branches_pinned = consider_version_branches_pinned
      @dependency_source_details = dependency_source_details
    end

    sig { returns(T::Boolean) }
    def git_dependency?
      return false if dependency_source_details.nil?

      dependency_source_details&.fetch(:type) == "git"
    end

    # rubocop:disable Metrics/PerceivedComplexity
    sig { returns(T::Boolean) }
    def pinned?
      raise "Not a git dependency!" unless git_dependency?

      branch = dependency_source_details&.fetch(:branch)

      return false if ref.nil?
      return false if branch == ref
      return true if branch
      return true if dependency.version&.start_with?(T.must(ref))

      # If the specified `ref` is actually a tag, we're pinned
      return true if local_upload_pack&.match?(%r{ refs/tags/#{ref}$})

      # Assume we're pinned unless the specified `ref` is actually a branch
      return true unless local_upload_pack&.match?(%r{ refs/heads/#{ref}$})

      # TODO: Research whether considering branches that look like versions pinned makes sense for all ecosystems
      @consider_version_branches_pinned && version_tag?(T.must(ref))
    end
    # rubocop:enable Metrics/PerceivedComplexity

    sig { returns(T::Boolean) }
    def pinned_ref_looks_like_version?
      return false unless pinned?

      version_tag?(T.must(ref))
    end

    sig { returns(T::Boolean) }
    def pinned_ref_looks_like_commit_sha?
      return false unless ref && ref_looks_like_commit_sha?(T.must(ref))

      return false unless pinned?

      local_repo_git_metadata_fetcher.head_commit_for_ref(T.must(ref)).nil?
    end

    sig { returns(T.nilable(String)) }
    def head_commit_for_pinned_ref
      local_repo_git_metadata_fetcher.head_commit_for_ref_sha(T.must(ref))
    end

    sig { params(ref: String).returns(T::Boolean) }
    def ref_looks_like_commit_sha?(ref)
      ref.match?(/^[0-9a-f]{6,40}$/)
    end

    sig { params(version: T.any(String, Gem::Version)).returns(T::Boolean) }
    def branch_or_ref_in_release?(version)
      pinned_ref_in_release?(version) || branch_behind_release?(version)
    end

    sig { returns(T.nilable(String)) }
    def head_commit_for_current_branch
      ref = ref_or_branch || "HEAD"

      sha = head_commit_for_local_branch(ref)
      return sha if pinned? || sha

      raise Dependabot::GitDependencyReferenceNotFound, dependency.name
    end

    sig { params(name: String).returns(T.nilable(String)) }
    def head_commit_for_local_branch(name)
      local_repo_git_metadata_fetcher.head_commit_for_ref(name)
    end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def local_ref_for_latest_version_matching_existing_precision
      allowed_refs = local_tag_for_pinned_sha ? allowed_version_tags : allowed_version_refs

      max_local_tag_for_current_precision(allowed_refs)
    end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def local_ref_for_latest_version_lower_precision
      allowed_refs = local_tag_for_pinned_sha ? allowed_version_tags : allowed_version_refs

      max_local_tag_for_lower_precision(allowed_refs)
    end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def local_tag_for_latest_version
      max_local_tag(allowed_version_tags)
    end

    sig { returns(T::Array[T.nilable(T::Hash[Symbol, T.untyped])]) }
    def local_tags_for_allowed_versions_matching_existing_precision
      select_matching_existing_precision(allowed_version_tags).map { |t| to_local_tag(t) }
    end

    sig { returns(T::Array[T.nilable(T::Hash[Symbol, T.untyped])]) }
    def local_tags_for_allowed_versions
      allowed_version_tags.map { |t| to_local_tag(t) }
    end

    sig { returns(T::Array[Dependabot::GitRef]) }
    def allowed_version_tags
      allowed_versions(local_tags)
    end

    sig { returns(T::Array[Dependabot::GitRef]) }
    def allowed_version_refs
      allowed_versions(local_refs)
    end

    sig { returns(T.nilable(Gem::Version)) }
    def current_version
      return unless dependency.version && version_tag?(T.must(dependency.version))

      version_from_ref(T.must(dependency.version))
    end

    sig { params(tags: T::Array[Dependabot::GitRef]).returns(T::Array[T.any(Dependabot::GitRef, Gem::Version)]) }
    def filter_lower_versions(tags)
      return tags unless current_version

      versions = tags.map do |t|
        version_from_tag(t)
      end

      versions.select do |version|
        version > current_version
      end
    end

    sig { returns(T.nilable(String)) }
    def most_specific_tag_equivalent_to_pinned_ref
      commit_sha = head_commit_for_local_branch(T.must(ref))
      most_specific_version_tag_for_sha(commit_sha)
    end

    sig { returns(T.nilable(String)) }
    def local_tag_for_pinned_sha
      return unless pinned_ref_looks_like_commit_sha?

      @local_tag_for_pinned_sha = T.let(
        most_specific_version_tag_for_sha(ref),
        T.nilable(String)
      )
    end

    sig { returns(T.nilable(Gem::Version)) }
    def version_for_pinned_sha
      return unless local_tag_for_pinned_sha && version_class.correct?(local_tag_for_pinned_sha)

      version_class.new(local_tag_for_pinned_sha)
    end

    sig { returns(T::Boolean) }
    def git_repo_reachable?
      local_upload_pack
      true
    rescue Dependabot::GitDependenciesNotReachable
      false
    end

    sig { returns(T.nilable(T::Hash[T.any(Symbol, String), T.untyped])) }
    def dependency_source_details
      @dependency_source_details || dependency.source_details(allowed_types: ["git"])
    end

    sig { params(commit_sha: T.nilable(String)).returns(T.nilable(String)) }
    def most_specific_version_tag_for_sha(commit_sha)
      tags = local_tags.select { |t| t.commit_sha == commit_sha && version_class.correct?(t.name) }
                       .sort_by { |t| version_class.new(t.name) }
      return if tags.empty?

      tags[-1]&.name
    end

    private

    sig { returns(Dependabot::Dependency) }
    attr_reader :dependency

    sig { returns(T::Array[Dependabot::Credential]) }
    attr_reader :credentials

    sig { returns(T::Array[String]) }
    attr_reader :ignored_versions

    sig { params(tags: T::Array[Dependabot::GitRef]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def max_local_tag_for_current_precision(tags)
      max_local_tag(select_matching_existing_precision(tags))
    end

    sig { params(tags: T::Array[Dependabot::GitRef]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def max_local_tag_for_lower_precision(tags)
      max_local_tag(select_lower_precision(tags))
    end

    sig { params(tags: T::Array[Dependabot::GitRef]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def max_local_tag(tags)
      max_version_tag = tags.max_by { |t| version_from_tag(t) }

      to_local_tag(max_version_tag)
    end

    # Find the latest version with the same precision as the pinned version.
    sig { params(tags: T::Array[Dependabot::GitRef]).returns(T::Array[Dependabot::GitRef]) }
    def select_matching_existing_precision(tags)
      current_precision = precision(T.must(dependency.version))

      tags.select { |tag| precision(scan_version(tag.name)) == current_precision }
    end

    # Find the latest version with a lower precision as the pinned version.
    sig { params(tags: T::Array[Dependabot::GitRef]).returns(T::Array[Dependabot::GitRef]) }
    def select_lower_precision(tags)
      current_precision = precision(T.must(dependency.version))

      tags.select { |tag| precision(scan_version(tag.name)) <= current_precision }
    end

    sig { params(version: String).returns(Integer) }
    def precision(version)
      version.split(".").length
    end

    sig { params(local_tags: T::Array[Dependabot::GitRef]).returns(T::Array[Dependabot::GitRef]) }
    def allowed_versions(local_tags)
      tags =
        local_tags
        .select { |t| version_tag?(t.name) && matches_existing_prefix?(t.name) }
      filtered = tags
                 .reject { |t| tag_included_in_ignore_requirements?(t) }
      if @raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(tags).any?
        raise Dependabot::AllVersionsIgnored
      end

      filtered
        .reject { |t| tag_is_prerelease?(t) && !wants_prerelease? }
    end

    sig { params(version: T.any(String, Gem::Version)).returns(T::Boolean) }
    def pinned_ref_in_release?(version)
      raise "Not a git dependency!" unless git_dependency?

      return false unless pinned?
      return false if listing_source_url.nil?

      tag = listing_tag_for_version(version.to_s)
      return false unless tag

      commit_included_in_tag?(
        commit: T.must(ref),
        tag: tag,
        allow_identical: true
      )
    end

    sig { params(version: T.any(String, Gem::Version)).returns(T::Boolean) }
    def branch_behind_release?(version)
      raise "Not a git dependency!" unless git_dependency?

      return false if ref_or_branch.nil?
      return false if listing_source_url.nil?

      tag = listing_tag_for_version(version.to_s)
      return false unless tag

      # Check if behind, excluding the case where it's identical, because
      # we normally wouldn't switch you from tracking master to a release.
      commit_included_in_tag?(
        commit: T.must(ref_or_branch),
        tag: tag,
        allow_identical: false
      )
    end

    sig { returns(T.nilable(String)) }
    def local_upload_pack
      local_repo_git_metadata_fetcher.upload_pack
    end

    sig { returns(T::Array[Dependabot::GitRef]) }
    def local_refs
      handle_tag_prefix(local_repo_git_metadata_fetcher.refs_for_upload_pack)
    end

    sig { returns(T::Array[Dependabot::GitRef]) }
    def local_tags
      handle_tag_prefix(local_repo_git_metadata_fetcher.tags_for_upload_pack)
    end

    sig { params(tags: T::Array[Dependabot::GitRef]).returns(T::Array[Dependabot::GitRef]) }
    def handle_tag_prefix(tags)
      if dependency_source_details&.fetch(:ref, nil)&.start_with?("tags/")
        tags = tags.map do |tag|
          tag.dup.tap { |t| t.name = "tags/#{tag.name}" }
        end
      end

      tags
    end

    sig do
      params(
        tag: String,
        commit: String,
        allow_identical: T::Boolean
      )
        .returns(T::Boolean)
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

    sig { params(ref1: String, ref2: String).returns(String) }
    def github_commit_comparison_status(ref1, ref2)
      client = Clients::GithubWithRetries
               .for_github_dot_com(credentials: credentials)

      # TODO: create this method instead of relying on method_missing
      T.unsafe(client).compare(listing_source_repo, ref1, ref2).status
    end

    sig { params(ref1: String, ref2: String).returns(String) }
    def gitlab_commit_comparison_status(ref1, ref2)
      client = Clients::GitlabWithRetries
               .for_gitlab_dot_com(credentials: credentials)

      comparison = T.unsafe(client).compare(listing_source_repo, ref1, ref2)

      if comparison.commits.none? then "behind"
      elsif comparison.compare_same_ref then "identical"
      else
        "ahead"
      end
    end

    sig { params(ref1: String, ref2: String).returns(String) }
    def bitbucket_commit_comparison_status(ref1, ref2)
      url = "https://api.bitbucket.org/2.0/repositories/" \
            "#{listing_source_repo}/commits/?" \
            "include=#{ref2}&exclude=#{ref1}"

      client = Clients::BitbucketWithRetries
               .for_bitbucket_dot_org(credentials: credentials)

      response = T.unsafe(client).get(url)

      # Conservatively assume that ref2 is ahead in the equality case, of
      # if we get an unexpected format (e.g., due to a 404)
      if JSON.parse(response.body).fetch("values", ["x"]).none? then "behind"
      else
        "ahead"
      end
    end

    sig { returns(T.nilable(String)) }
    def ref_or_branch
      ref || dependency_source_details&.fetch(:branch)
    end

    sig { returns(T.nilable(String)) }
    def ref
      dependency_source_details&.fetch(:ref)
    end

    sig { params(tag: String).returns(T::Boolean) }
    def version_tag?(tag)
      tag.match?(VERSION_REGEX)
    end

    sig { params(tag: String).returns(T::Boolean) }
    def matches_existing_prefix?(tag)
      return true unless ref_or_branch

      if version_tag?(T.must(ref_or_branch))
        same_prefix?(T.must(ref_or_branch), tag)
      else
        local_tag_for_pinned_sha.nil? || same_prefix?(T.must(local_tag_for_pinned_sha), tag)
      end
    end

    sig { params(tag: String, other_tag: String).returns(T::Boolean) }
    def same_prefix?(tag, other_tag)
      tag.gsub(VERSION_REGEX, "").gsub(/v$/i, "") ==
        other_tag.gsub(VERSION_REGEX, "").gsub(/v$/i, "")
    end

    sig { params(tag: T.nilable(Dependabot::GitRef)).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
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

    sig { returns(T.nilable(String)) }
    def listing_source_url
      @listing_source_url ||= T.let(
        begin
          # Remove the git source, so the metadata finder looks on the
          # registry
          candidate_dep = Dependency.new(
            name: dependency.name,
            version: dependency.version,
            requirements: [],
            package_manager: dependency.package_manager
          )

          MetadataFinders
            .for_package_manager(dependency.package_manager)
            .new(dependency: candidate_dep, credentials: credentials)
            .source_url
        end,
        T.nilable(String)
      )
    end

    sig { returns(T.nilable(String)) }
    def listing_source_repo
      return unless listing_source_url

      Source.from_url(listing_source_url)&.repo
    end

    sig { params(version: String).returns(T.nilable(String)) }
    def listing_tag_for_version(version)
      listing_tags
        .find { |t| t.name =~ /(?:[^0-9\.]|\A)#{Regexp.escape(version)}\z/ }
        &.name
    end

    sig { returns(T::Array[Dependabot::GitRef]) }
    def listing_tags
      return [] unless listing_source_url

      @listing_tags ||= T.let(
        begin
          tags = listing_repo_git_metadata_fetcher.tags

          if dependency_source_details&.fetch(:ref, nil)&.start_with?("tags/")
            tags = tags.map do |tag|
              tag.dup.tap { |t| t.name = "tags/#{tag.name}" }
            end
          end

          tags
        rescue GitDependenciesNotReachable
          []
        end,
        T.nilable(T::Array[Dependabot::GitRef])
      )
    end

    sig { returns(T.nilable(String)) }
    def listing_upload_pack
      return unless listing_source_url

      listing_repo_git_metadata_fetcher.upload_pack
    end

    sig { returns(T::Array[Dependabot::Requirement]) }
    def ignore_requirements
      ignored_versions.flat_map { |req| requirement_class.requirements_array(req) }
    end

    sig { returns(T::Boolean) }
    def wants_prerelease?
      return false unless dependency_source_details&.fetch(:ref, nil)
      return false unless pinned_ref_looks_like_version?

      version = version_from_ref(T.must(ref))
      version.prerelease?
    end

    sig { params(tag: Dependabot::GitRef).returns(T::Boolean) }
    def tag_included_in_ignore_requirements?(tag)
      version = version_from_tag(tag)
      ignore_requirements.any? { |r| r.satisfied_by?(version) }
    end

    sig { params(tag: Dependabot::GitRef).returns(T::Boolean) }
    def tag_is_prerelease?(tag)
      version_from_tag(tag).prerelease?
    end

    sig { params(tag: Dependabot::GitRef).returns(Gem::Version) }
    def version_from_tag(tag)
      version_from_ref(tag.name)
    end

    sig { params(name: String).returns(Gem::Version) }
    def version_from_ref(name)
      version_class.new(scan_version(name))
    end

    sig { params(name: String).returns(String) }
    def scan_version(name)
      T.must(T.must(name.match(VERSION_REGEX)).named_captures.fetch("version"))
    end

    sig { returns(T.class_of(Gem::Version)) }
    def version_class
      @version_class ||= T.let(
        dependency.version_class,
        T.nilable(T.class_of(Gem::Version))
      )
    end

    sig { returns(T.class_of(Dependabot::Requirement)) }
    def requirement_class
      @requirement_class ||= T.let(
        dependency.requirement_class,
        T.nilable(T.class_of(Dependabot::Requirement))
      )
    end

    sig { returns(Dependabot::GitMetadataFetcher) }
    def local_repo_git_metadata_fetcher
      @local_repo_git_metadata_fetcher ||=
        T.let(
          GitMetadataFetcher.new(
            url: dependency_source_details&.fetch(:url),
            credentials: credentials
          ),
          T.nilable(Dependabot::GitMetadataFetcher)
        )
    end

    sig { returns(Dependabot::GitMetadataFetcher) }
    def listing_repo_git_metadata_fetcher
      @listing_repo_git_metadata_fetcher ||=
        T.let(
          GitMetadataFetcher.new(
            url: T.must(listing_source_url),
            credentials: credentials
          ),
          T.nilable(Dependabot::GitMetadataFetcher)
        )
    end
  end
  # rubocop:enable Metrics/ClassLength
end
