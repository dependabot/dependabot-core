# frozen_string_literal: true

require "excon"
require "gitlab"
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

      return sha_for_update_pack_line(line) if line
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
        commit_sha: tag.commit_sha,
        tag_sha: tag.tag_sha
      }
    end

    private

    attr_reader :dependency, :credentials

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
      @local_upload_pack ||=
        fetch_upload_pack_for(dependency_source_details.fetch(:url))
    end

    def local_tags
      return [] unless local_upload_pack
      tags_for_upload_pack(local_upload_pack)
    end

    def tags_for_upload_pack(upload_pack)
      peeled_lines = []
      unpeeled_lines = []

      upload_pack.lines.each do |line|
        next unless line.split(" ").last.start_with?("refs/tags")

        if line.strip.end_with?("^{}") then peeled_lines << line
        else unpeeled_lines << line
        end
      end

      unpeeled_lines.map do |line|
        tag_name    = line.split(" refs/tags/").last.strip
        tag_sha     = sha_for_update_pack_line(line)
        peeled_line = peeled_lines.find do |pl|
          pl.split(" refs/tags/").last.strip == "#{tag_name}^{}"
        end

        commit_sha =
          if peeled_line then sha_for_update_pack_line(peeled_line)
          else tag_sha
          end

        OpenStruct.new(
          name: tag_name,
          tag_sha: tag_sha,
          commit_sha: commit_sha
        )
      end
    end

    def fetch_upload_pack_for(uri)
      original_uri = uri
      bare_uri = uri.sub(%r{.*?://}, "").sub("git@", "").sub(":", "/")
      cred = credentials.select { |c| c["host"] }.
             sort_by { |c| c["host"].length * -1 }.
             find { |c| bare_uri.start_with?(c["host"]) }

      uri =
        if cred
          auth = cred["token"] || "#{cred['username']}:#{cred['password']}"
          "https://#{auth}@#{bare_uri}"
        else "https://#{bare_uri}"
        end

      uri = uri.gsub(%r{/$}, "")
      uri += ".git" unless uri.end_with?(".git")
      uri += "/info/refs?service=git-upload-pack"

      response = Excon.get(
        uri,
        idempotent: true,
        omit_default_port: true,
        middlewares: SharedHelpers.excon_middleware
      )

      return response.body if response.status == 200
      raise Dependabot::GitDependenciesNotReachable, [original_uri]
    rescue Excon::Error::Socket, Excon::Error::Timeout
      raise Dependabot::GitDependenciesNotReachable, [original_uri]
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
    rescue Octokit::NotFound, Gitlab::Error::NotFound
      false
    end

    def github_commit_comparison_status(ref1, ref2)
      access_token = credentials.
                     find { |cred| cred["host"] == "github.com" }.
                     fetch("password")

      client = GithubClientWithRetries.new(access_token: access_token)
      client.compare(listing_source_repo, ref1, ref2).status
    end

    def gitlab_commit_comparison_status(ref1, ref2)
      access_token = credentials.
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
      token = credentials.
              find { |cred| cred["host"] == "bitbucket.org" }&.
              fetch("token")

      auth_header =
        if token.nil? then {}
        elsif token.include?(":")
          encoded_token = Base64.encode64(token).chomp
          { "Authorization" => "Basic #{encoded_token}" }
        else { "Authorization" => "Bearer #{token}" }
        end

      url = "https://api.bitbucket.org/2.0/repositories/"\
            "#{listing_source_repo}/commits/?"\
            "include=#{ref2}&exclude=#{ref1}"

      response = Excon.get(url,
                           headers: auth_header,
                           idempotent: true,
                           omit_default_port: true,
                           middlewares: SharedHelpers.excon_middleware)

      # Conservatively assume that ref2 is ahead in the equality case, of
      # if we get an unexpected format (e.g., due to a 404)
      if JSON.parse(response.body).fetch("values", ["x"]).none? then "behind"
      else "ahead"
      end
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
      return [] unless listing_upload_pack
      tags_for_upload_pack(listing_upload_pack)
    rescue GitDependenciesNotReachable
      []
    end

    def listing_upload_pack
      return unless listing_source_url
      @listing_upload_pack ||= fetch_upload_pack_for(listing_source_url)
    end

    def version_class
      Utils.version_class_for_package_manager(dependency.package_manager)
    end

    def sha_for_update_pack_line(line)
      line.split(" ").first.chars.last(40).join
    end
  end
end
