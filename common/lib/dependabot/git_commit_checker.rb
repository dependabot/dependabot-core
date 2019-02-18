# frozen_string_literal: true

require "excon"
require "gitlab"
require "dependabot/clients/github_with_retries"
require "dependabot/metadata_finders"
require "dependabot/errors"
require "dependabot/utils"
require "dependabot/source"
require "dependabot/dependency"
require "dependabot/git_metadata_fetcher"

# rubocop:disable Metrics/ClassLength
module Dependabot
  class GitCommitChecker
    VERSION_REGEX = /(?<version>[0-9]+\.[0-9]+(?:\.[a-zA-Z0-9\-]+)*)$/.freeze

    def initialize(dependency:, credentials:, ignored_versions: [],
                   requirement_class: nil, version_class: nil)
      @dependency = dependency
      @credentials = credentials
      @ignored_versions = ignored_versions
      @requirement_class = requirement_class
      @version_class = version_class
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

      # Check the specified `ref` isn't actually a branch
      !local_upload_pack.match?("refs/heads/#{ref}")
    end

    def pinned_ref_looks_like_version?
      return false unless pinned?

      dependency_source_details.fetch(:ref).match?(VERSION_REGEX)
    end

    def branch_or_ref_in_release?(version)
      pinned_ref_in_release?(version) || branch_behind_release?(version)
    end

    def head_commit_for_current_branch
      return dependency.version if pinned?

      branch_ref = ref_or_branch ? "refs/heads/#{ref_or_branch}" : "HEAD"

      # Remove the opening clause of the upload pack as this isn't always
      # followed by a line break. When it isn't (e.g., with Bitbucket) it causes
      # problems for our `sha_for_update_pack_line` logic
      line = local_upload_pack.
             gsub(/.*git-upload-pack/, "").
             lines.find { |l| l.include?(" #{branch_ref}") }

      return sha_for_update_pack_line(line) if line

      raise Dependabot::GitDependencyReferenceNotFound, dependency.name
    end

    def local_tag_for_latest_version
      tag =
        local_tags.
        select { |t| t.name.match?(VERSION_REGEX) }.
        reject { |t| tag_included_in_ignore_reqs?(t) }.
        reject { |t| tag_is_prerelease?(t) && !wants_prerelease? }.
        max_by do |t|
          version = t.name.match(VERSION_REGEX).named_captures.fetch("version")
          version_class.new(version)
        end

      return unless tag

      {
        tag: tag.name,
        commit_sha: tag.commit_sha,
        tag_sha: tag.tag_sha
      }
    end

    def git_repo_reachable?
      local_upload_pack
      true
    rescue Dependabot::GitDependenciesNotReachable
      false
    end

    private

    attr_reader :dependency, :credentials, :ignored_versions

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

    def local_tags
      tags = local_repo_git_metadata_fetcher.tags

      if dependency_source_details&.fetch(:ref, nil)&.start_with?("tags/")
        tags = tags.map { |tag| tag.tap { |t| t.name = "tags/#{tag.name}" } }
      end

      tags
    end

    def commit_included_in_tag?(tag:, commit:, allow_identical: false)
      status =
        case Source.from_url(listing_source_url)&.provider
        when "github" then github_commit_comparison_status(tag, commit)
        when "gitlab" then gitlab_commit_comparison_status(tag, commit)
        when "bitbucket" then bitbucket_commit_comparison_status(tag, commit)
        else raise "Unknown source"
        end

      return true if status == "behind"

      allow_identical && status == "identical"
    rescue Octokit::NotFound, Gitlab::Error::NotFound,
           Octokit::InternalServerError
      false
    end

    def github_commit_comparison_status(ref1, ref2)
      client = Clients::GithubWithRetries.
               for_github_dot_com(credentials: credentials)

      client.compare(listing_source_repo, ref1, ref2).status
    end

    def gitlab_commit_comparison_status(ref1, ref2)
      access_token = credentials.
                     select { |cred| cred["type"] == "git_source" }.
                     find { |cred| cred["host"] == "gitlab.com" }&.
                     fetch("token")

      client = Gitlab.client(endpoint: "https://gitlab.com/api/v4",
                             private_token: access_token.to_s)

      comparison = client.compare(listing_source_repo, ref1, ref2)

      if comparison.commits.none? then "behind"
      elsif comparison.compare_same_ref then "identical"
      else "ahead"
      end
    end

    def bitbucket_commit_comparison_status(ref1, ref2)
      url = "https://api.bitbucket.org/2.0/repositories/"\
            "#{listing_source_repo}/commits/?"\
            "include=#{ref2}&exclude=#{ref1}"

      response = Excon.get(url,
                           headers: bitbucket_auth_header,
                           idempotent: true,
                           **SharedHelpers.excon_defaults)

      # Conservatively assume that ref2 is ahead in the equality case, of
      # if we get an unexpected format (e.g., due to a 404)
      if JSON.parse(response.body).fetch("values", ["x"]).none? then "behind"
      else "ahead"
      end
    end

    def bitbucket_auth_header
      token = credentials.
              select { |cred| cred["type"] == "git_source" }.
              find { |cred| cred["host"] == "bitbucket.org" }&.
              fetch("token")

      if token.nil? then {}
      elsif token.include?(":")
        encoded_token = Base64.encode64(token).delete("\n")
        { "Authorization" => "Basic #{encoded_token}" }
      elsif Base64.decode64(token).ascii_only? &&
            Base64.decode64(token).include?(":")
        { "Authorization" => "Basic #{token.delete("\n")}" }
      else
        { "Authorization" => "Bearer #{token}" }
      end
    end

    def dependency_source_details
      sources =
        dependency.requirements.map { |r| r.fetch(:source) }.uniq.compact

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

      tags = listing_repo_git_metadata_fetcher.tags

      if dependency_source_details&.fetch(:ref, nil)&.start_with?("tags/")
        tags = tags.map { |tag| tag.tap { |t| t.name = "tags/#{tag.name}" } }
      end

      tags
    rescue GitDependenciesNotReachable
      []
    end

    def listing_upload_pack
      return unless listing_source_url

      listing_repo_git_metadata_fetcher.upload_pack
    end

    def ignore_reqs
      ignored_versions.map { |req| requirement_class.new(req.split(",")) }
    end

    def wants_prerelease?
      return false unless dependency_source_details&.fetch(:ref, nil)
      return false unless pinned_ref_looks_like_version?

      version = dependency_source_details.fetch(:ref).match(VERSION_REGEX).
                named_captures.fetch("version")
      version_class.new(version).prerelease?
    end

    def tag_included_in_ignore_reqs?(tag)
      version = tag.name.match(VERSION_REGEX).named_captures.fetch("version")
      ignore_reqs.any? { |r| r.satisfied_by?(version_class.new(version)) }
    end

    def tag_is_prerelease?(tag)
      version = tag.name.match(VERSION_REGEX).named_captures.fetch("version")
      version_class.new(version).prerelease?
    end

    def version_class
      return @version_class if @version_class

      Utils.version_class_for_package_manager(dependency.package_manager)
    end

    def requirement_class
      return @requirement_class if @requirement_class

      Utils.requirement_class_for_package_manager(dependency.package_manager)
    end

    def sha_for_update_pack_line(line)
      line.split(" ").first.chars.last(40).join
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
# rubocop:enable Metrics/ClassLength
