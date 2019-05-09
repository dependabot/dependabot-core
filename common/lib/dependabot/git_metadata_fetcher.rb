# frozen_string_literal: true

require "excon"
require "dependabot/errors"

module Dependabot
  class GitMetadataFetcher
    KNOWN_HOSTS = /github\.com|bitbucket\.org|gitlab.com/.freeze

    def initialize(url:, credentials:)
      @url = url
      @credentials = credentials
    end

    def upload_pack
      @upload_pack ||= fetch_upload_pack_for(url)
    end

    def tags
      return [] unless upload_pack

      @tags ||= tags_for_upload_pack(upload_pack)
    end

    def ref_names
      @ref_names ||=
        upload_pack.lines.
        select { |l| l.split(" ")[-1].start_with?("refs/tags", "refs/heads") }.
        map { |line| line.split(%r{ refs/(tags|heads)/}).last.strip }.
        reject { |l| l.end_with?("^{}") }
    end

    private

    attr_reader :url, :credentials

    # rubocop:disable Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/PerceivedComplexity
    def fetch_upload_pack_for(uri)
      response = Excon.get(
        service_pack_uri(uri),
        idempotent: true,
        **SharedHelpers.excon_defaults
      )

      return response.body if response.status == 200
      if response.status >= 500 && uri.match?(KNOWN_HOSTS)
        raise "Server error at #{uri}: #{response.body}"
      end

      raise Dependabot::GitDependenciesNotReachable, [uri]
    rescue Excon::Error::Socket, Excon::Error::Timeout
      retry_count ||= 0
      retry_count += 1

      sleep(rand(0.9)) && retry if retry_count <= 2 && uri.match?(KNOWN_HOSTS)
      raise if uri.match?(KNOWN_HOSTS)

      raise Dependabot::GitDependenciesNotReachable, [uri]
    end
    # rubocop:enable Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/PerceivedComplexity

    def tags_for_upload_pack(upload_pack)
      peeled_lines = []

      result = upload_pack.lines.each_with_object({}) do |line, res|
        next unless line.split(" ").last.start_with?("refs/tags")

        peeled_lines << line && next if line.strip.end_with?("^{}")

        tag_name = line.split(" refs/tags/").last.strip
        sha = sha_for_update_pack_line(line)

        res[tag_name] =
          OpenStruct.new(name: tag_name, tag_sha: sha, commit_sha: sha)
      end

      # Loop through the peeled lines, updating the commit_sha for any matching
      # tags in our results hash
      peeled_lines.each do |line|
        tag_name = line.split(" refs/tags/").last.strip.gsub(/\^{}$/, "")
        next unless result[tag_name]

        result[tag_name].commit_sha = sha_for_update_pack_line(line)
      end

      result.values
    end

    def service_pack_uri(uri)
      service_pack_uri = uri_with_auth(uri)
      service_pack_uri = service_pack_uri.gsub(%r{/$}, "")
      service_pack_uri += ".git" unless service_pack_uri.end_with?(".git")
      service_pack_uri + "/info/refs?service=git-upload-pack"
    end

    def uri_with_auth(uri)
      bare_uri =
        if uri.include?("git@") then uri.split("git@").last.sub(":", "/")
        else uri.sub(%r{.*?://}, "")
        end
      cred = credentials.select { |c| c["type"] == "git_source" }.
             find { |c| bare_uri.start_with?(c["host"]) }

      if bare_uri.match?(%r{[^/]+:[^/]+@})
        # URI already has authentication details
        "https://#{bare_uri}"
      elsif cred&.fetch("username", nil) && cred&.fetch("password", nil)
        # URI doesn't have authentication details, but we have credentials
        auth_string = "#{cred.fetch('username')}:#{cred.fetch('password')}"
        "https://#{auth_string}@#{bare_uri}"
      else
        # No credentials, so just return the https URI
        "https://#{bare_uri}"
      end
    end

    def sha_for_update_pack_line(line)
      line.split(" ").first.chars.last(40).join
    end
  end
end
