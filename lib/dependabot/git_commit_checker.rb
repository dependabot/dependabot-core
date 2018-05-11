# frozen_string_literal: true

require "excon"
require "dependabot/github_client_with_retries"
require "dependabot/metadata_finders"
require "dependabot/errors"
require "dependabot/utils"
require "dependabot/source"

module Dependabot
  class GitCommitChecker
    VERSION_REGEX = /(?<version>[0-9]+\.[0-9]+(?:\.[a-zA-Z0-9\-]+)*)$/

    def initialize(dependency:, credentials:)
      @dependency = dependency
      @credentials = credentials
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
      line = local_upload_pack.lines.find { |l| l.include?(branch_ref) }

      return line.split(" ").first.chars.last(40).join if line
      raise Dependabot::GitDependencyReferenceNotFound, dependency.name
    end

    def local_tag_for_latest_version
      tag =
        local_tags.
        select { |t| t.name.match?(VERSION_REGEX) }.
        max_by do |t|
          version = t.name.match(VERSION_REGEX).named_captures.fetch("version")
          version_class.new(version)
        end

      return unless tag
      {
        tag: tag.name,
        commit_sha: tag.commit.sha,
        tag_sha: local_tag_sha(tag.name)
      }
    end

    private

    attr_reader :dependency, :credentials

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

      return false if ref_or_branch.nil?
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

    def local_upload_pack
      @local_upload_pack ||=
        fetch_upload_pack_for(dependency_source_details.fetch(:url))
    end

    def fetch_upload_pack_for(uri)
      original_uri = uri
      bare_uri = uri.sub(%r{.*?://}, "").sub("git@", "").sub(":", "/")
      cred = credentials.
             find { |c| c["type"] == "git" && bare_uri.start_with?(c["host"]) }

      uri =
        if cred
          "https://#{cred['username']}:#{cred['password']}@#{bare_uri}"
        else
          "https://#{bare_uri}"
        end

      uri = uri.gsub(%r{/$}, "")
      uri += ".git" unless uri.end_with?(".git")
      uri += "/info/refs?service=git-upload-pack"

      response = Excon.get(
        uri,
        idempotent: true,
        middlewares: SharedHelpers.excon_middleware
      )

      return response.body if response.status == 200
      raise Dependabot::GitDependenciesNotReachable, [original_uri]
    rescue Excon::Error::Socket, Excon::Error::Timeout
      raise Dependabot::GitDependenciesNotReachable, [original_uri]
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
            new(dependency: candidate_dep, credentials: credentials).
            source_url
        end
    end

    def listing_source_hosted_on_github?
      return unless listing_source_url
      Source.from_url(listing_source_url)&.host == "github"
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
      return [] unless listing_source_hosted_on_github?
      @listing_tags ||= github_client.tags(listing_source_repo, per_page: 100)
    rescue Octokit::NotFound
      []
    end

    def local_source_url
      @local_source_url ||=
        MetadataFinders.
        for_package_manager(dependency.package_manager).
        new(dependency: dependency, credentials: credentials).
        source_url
    end

    def local_source_hosted_on_github?
      return unless local_source_url
      Source.from_url(local_source_url)&.host == "github"
    end

    def local_source_repo
      return unless local_source_url
      Source.from_url(local_source_url)&.repo
    end

    def local_tags
      return [] unless local_source_url
      return [] unless local_source_hosted_on_github?
      @local_tags ||= github_client.tags(local_source_repo, per_page: 100)
    rescue Octokit::NotFound
      []
    end

    def local_tag_sha(tag)
      @local_tag_shas ||= {}
      @local_tag_shas[tag] ||= {}
      if @local_tag_shas[tag][:lookup_attempted]
        return @local_tag_shas[tag][:sha]
      end
      @local_tag_shas[tag][:lookup_attempted] = true
      @local_tag_shas[tag][:sha] =
        github_client.ref(local_source_repo, "tags/#{tag}").object.sha
    end

    def github_client
      @github_client ||=
        Dependabot::GithubClientWithRetries.
        new(access_token: github_access_token)
    end

    def version_class
      Utils.version_class_for_package_manager(dependency.package_manager)
    end

    def github_access_token
      credentials.
        find { |cred| cred["host"] == "github.com" }.
        fetch("password")
    end
  end
end
