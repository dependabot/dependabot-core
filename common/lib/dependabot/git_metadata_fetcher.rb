# frozen_string_literal: true

require "excon"
require "dependabot/errors"

module Dependabot
  class GitMetadataFetcher
    KNOWN_HOSTS = /github\.com|bitbucket\.org|gitlab.com/i.freeze

    def initialize(url:, credentials:)
      @url = url
      @credentials = credentials
    end

    def upload_pack
      @upload_pack ||= fetch_upload_pack_for(url)
    rescue Octokit::ClientError
      raise Dependabot::GitDependenciesNotReachable, [url]
    end

    def tags
      return [] unless upload_pack

      @tags ||= tags_for_upload_pack
    end

    def ref_names
      refs_for_upload_pack.map(&:name)
    end

    def head_commit_for_ref(ref)
      if ref == "HEAD"
        # Remove the opening clause of the upload pack as this isn't always
        # followed by a line break. When it isn't (e.g., with Bitbucket) it
        # causes problems for our `sha_for_update_pack_line` logic
        line = upload_pack.gsub(/.*git-upload-pack/, "").
               lines.find { |l| l.include?(" HEAD") }
        return sha_for_update_pack_line(line) if line
      end

      refs_for_upload_pack.
        find { |r| r.name == ref }&.
        commit_sha
    end

    private

    attr_reader :url, :credentials

    # rubocop:disable Metrics/PerceivedComplexity
    def fetch_upload_pack_for(uri)
      response = fetch_raw_upload_pack_for(uri)
      return response.body if response.status == 200

      unless uri.match?(KNOWN_HOSTS)
        raise Dependabot::GitDependenciesNotReachable, [uri]
      end

      if response.status < 400
        raise "Unexpected response: #{response.status} - #{response.body}"
      end

      if uri.match?(/github\.com/i)
        response = response.data
        response[:response_headers] = response[:headers]
        raise Octokit::Error.from_response(response)
      end

      raise "Server error at #{uri}: #{response.body}" if response.status >= 500

      raise Dependabot::GitDependenciesNotReachable, [uri]
    rescue Excon::Error::Socket, Excon::Error::Timeout
      retry_count ||= 0
      retry_count += 1

      sleep(rand(0.9)) && retry if retry_count <= 2 && uri.match?(KNOWN_HOSTS)
      raise if uri.match?(KNOWN_HOSTS)

      raise Dependabot::GitDependenciesNotReachable, [uri]
    end
    # rubocop:enable Metrics/PerceivedComplexity

    def fetch_raw_upload_pack_for(uri)
      url = service_pack_uri(uri)
      url = url.rpartition("@").tap { |a| a.first.gsub!("@", "%40") }.join
      Excon.get(
        url,
        idempotent: true,
        **excon_defaults
      )
    end

    def tags_for_upload_pack
      refs_for_upload_pack.
        select { |ref| ref.ref_type == :tag }.
        map do |ref|
          OpenStruct.new(
            name: ref.name,
            tag_sha: ref.ref_sha,
            commit_sha: ref.commit_sha
          )
        end
    end

    def refs_for_upload_pack
      @refs_for_upload_pack ||= parse_refs_for_upload_pack
    end

    def parse_refs_for_upload_pack
      peeled_lines = []

      result = upload_pack.lines.each_with_object({}) do |line, res|
        full_ref_name = line.split(" ").last
        next unless full_ref_name.start_with?("refs/tags", "refs/heads")

        peeled_lines << line && next if line.strip.end_with?("^{}")

        ref_name = full_ref_name.sub(%r{^refs/(tags|heads)/}, "").strip
        sha = sha_for_update_pack_line(line)

        res[ref_name] = OpenStruct.new(
          name: ref_name,
          ref_sha: sha,
          ref_type: full_ref_name.start_with?("refs/tags") ? :tag : :head,
          commit_sha: sha
        )
      end

      # Loop through the peeled lines, updating the commit_sha for any
      # matching tags in our results hash
      peeled_lines.each do |line|
        ref_name = line.split(%r{ refs/(tags|heads)/}).
                   last.strip.gsub(/\^{}$/, "")
        next unless result[ref_name]

        result[ref_name].commit_sha = sha_for_update_pack_line(line)
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
        if uri.include?("git@") then uri.split("git@").last.sub(%r{:/?}, "/")
        else uri.sub(%r{.*?://}, "")
        end
      cred = credentials.select { |c| c["type"] == "git_source" }.
             find { |c| bare_uri.start_with?(c["host"]) }

      scheme = scheme_for_uri(uri)

      if bare_uri.match?(%r{[^/]+:[^/]+@})
        # URI already has authentication details
        "#{scheme}://#{bare_uri}"
      elsif cred&.fetch("username", nil) && cred&.fetch("password", nil)
        # URI doesn't have authentication details, but we have credentials
        auth_string = "#{cred.fetch('username')}:#{cred.fetch('password')}"
        "#{scheme}://#{auth_string}@#{bare_uri}"
      else
        # No credentials, so just return the http(s) URI
        "#{scheme}://#{bare_uri}"
      end
    end

    def scheme_for_uri(uri)
      if uri.match?(%r{^http://})
        "http"
      else
        "https"
      end
    end

    def sha_for_update_pack_line(line)
      line.split(" ").first.chars.last(40).join
    end

    def excon_defaults
      # Some git hosts are slow when returning a large number of tags
      SharedHelpers.excon_defaults.merge(read_timeout: 20)
    end
  end
end
