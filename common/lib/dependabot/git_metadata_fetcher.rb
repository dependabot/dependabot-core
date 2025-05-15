# typed: strict
# frozen_string_literal: true

require "excon"
require "open3"
require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/git_ref"
require "dependabot/credential"

module Dependabot
  class GitMetadataFetcher
    extend T::Sig

    KNOWN_HOSTS = /github\.com|bitbucket\.org|gitlab.com/i

    sig do
      params(
        url: String,
        credentials: T::Array[Dependabot::Credential]
      )
        .void
    end
    def initialize(url:, credentials:)
      @url = url
      @credentials = credentials
    end

    sig { returns(T.nilable(String)) }
    def upload_pack
      @upload_pack ||= T.let(fetch_upload_pack_for(url), T.nilable(String))
    rescue Octokit::ClientError
      raise Dependabot::GitDependenciesNotReachable, [url]
    end

    sig { returns(T::Array[GitRef]) }
    def tags
      return [] unless upload_pack

      @tags ||= T.let(
        tags_for_upload_pack.map do |ref|
          GitRef.new(
            name: ref.name,
            tag_sha: ref.ref_sha,
            commit_sha: ref.commit_sha
          )
        end,
        T.nilable(T::Array[GitRef])
      )
    end

    sig { returns(T::Array[GitRef]) }
    def tags_for_upload_pack
      @tags_for_upload_pack ||= T.let(
        refs_for_upload_pack.select { |ref| ref.ref_type == RefType::Tag },
        T.nilable(T::Array[GitRef])
      )
    end

    sig { returns(T::Array[GitRef]) }
    def refs_for_upload_pack
      @refs_for_upload_pack ||= T.let(parse_refs_for_upload_pack, T.nilable(T::Array[GitRef]))
    end

    sig { returns(T::Array[String]) }
    def ref_names
      refs_for_upload_pack.map(&:name)
    end

    sig { params(ref: String).returns(T.nilable(String)) }
    def head_commit_for_ref(ref)
      if ref == "HEAD"
        # Remove the opening clause of the upload pack as this isn't always
        # followed by a line break. When it isn't (e.g., with Bitbucket) it
        # causes problems for our `sha_for_update_pack_line` logic. The format
        # of this opening clause is documented at
        # https://git-scm.com/docs/http-protocol#_smart_server_response
        line = T.must(upload_pack).gsub(/^[0-9a-f]{4}# service=git-upload-pack/, "")
                .lines.find { |l| l.include?(" HEAD") }
        return sha_for_update_pack_line(line) if line
      end

      refs_for_upload_pack
        .find { |r| r.name == ref }
        &.commit_sha
    end

    sig { params(ref: String).returns(T.nilable(String)) }
    def head_commit_for_ref_sha(ref)
      refs_for_upload_pack
        .find { |r| r.ref_sha == ref }
        &.commit_sha
    end

    private

    sig { returns(String) }
    attr_reader :url

    sig { returns(T::Array[Dependabot::Credential]) }
    attr_reader :credentials

    sig { params(uri: String).returns(String) }
    def fetch_upload_pack_for(uri)
      response = fetch_raw_upload_pack_for(uri)
      return response.body if response.status == 200

      response_with_git = fetch_raw_upload_pack_with_git_for(uri)
      return response_with_git.body if response_with_git.status == 200

      raise Dependabot::GitDependenciesNotReachable, [uri] unless uri.match?(KNOWN_HOSTS)

      raise "Unexpected response: #{response.status} - #{response.body}" if response.status < 400

      if uri.match?(/github\.com/i)
        response = response.data
        response[:response_headers] = response[:headers]
        raise Octokit::Error.from_response(response)
      end

      raise "Server error at #{uri}: #{response.body}" if response.status >= 500

      raise Dependabot::GitDependenciesNotReachable, [uri]
    rescue Excon::Error::Socket, Excon::Error::Timeout
      raise if uri.match?(KNOWN_HOSTS)

      raise Dependabot::GitDependenciesNotReachable, [uri]
    end

    sig { params(uri: String).returns(Excon::Response) }
    def fetch_raw_upload_pack_for(uri)
      url = service_pack_uri(uri)
      url = url.rpartition("@").tap { |a| a.first.gsub!("@", "%40") }.join
      Excon.get(
        url,
        idempotent: true,
        **excon_defaults
      )
    end

    sig { params(uri: String).returns(T.untyped) }
    def fetch_raw_upload_pack_with_git_for(uri)
      service_pack_uri = uri
      service_pack_uri += ".git" unless service_pack_uri.end_with?(".git") || skip_git_suffix(uri)

      env = { "PATH" => ENV.fetch("PATH", nil), "GIT_TERMINAL_PROMPT" => "0" }
      command = "git ls-remote #{service_pack_uri}"
      command = SharedHelpers.escape_command(command)

      begin
        stdout, stderr, process = Open3.capture3(env, command)
        # package the command response like a HTTP response so error handling remains unchanged
      rescue Errno::ENOENT => e # thrown when `git` isn't installed...
        OpenStruct.new(body: e.message, status: 500)
      else
        if process.success?
          OpenStruct.new(body: stdout, status: 200)
        else
          OpenStruct.new(body: stderr, status: 500)
        end
      end
    end

    sig { returns(T::Array[GitRef]) }
    def parse_refs_for_upload_pack
      peeled_lines = []

      result = T.must(upload_pack).lines.each_with_object({}) do |line, res|
        full_ref_name = T.must(line.split.last)
        next unless full_ref_name.start_with?("refs/tags", "refs/heads")

        (peeled_lines << line) && next if line.strip.end_with?("^{}")

        ref_name = full_ref_name.sub(%r{^refs/(tags|heads)/}, "").strip
        sha = sha_for_update_pack_line(line)

        res[ref_name] = GitRef.new(
          name: ref_name,
          ref_sha: sha,
          ref_type: full_ref_name.start_with?("refs/tags") ? RefType::Tag : RefType::Head,
          commit_sha: sha
        )
      end

      # Loop through the peeled lines, updating the commit_sha for any
      # matching tags in our results hash
      peeled_lines.each do |line|
        ref_name = line.split(%r{ refs/(tags|heads)/})
                       .last.strip.gsub(/\^{}$/, "")
        next unless result[ref_name]

        result[ref_name].commit_sha = sha_for_update_pack_line(line)
      end

      result.values
    end

    sig { params(uri: String).returns(String) }
    def service_pack_uri(uri)
      service_pack_uri = uri_with_auth(uri)
      service_pack_uri = service_pack_uri.gsub(%r{/$}, "")
      service_pack_uri += ".git" unless service_pack_uri.end_with?(".git") || skip_git_suffix(uri)
      service_pack_uri + "/info/refs?service=git-upload-pack"
    end

    sig { params(uri: String).returns(T::Boolean) }
    def skip_git_suffix(uri)
      # TODO: Unlike the other providers (GitHub, GitLab, BitBucket), as of 2023-01-18 Azure DevOps does not support the
      # ".git" suffix. It will return a 404.
      # So skip adding ".git" if looks like an ADO URI.
      # There's no access to the source object here, so have to check the URI instead.
      # Even if we had the current source object, the URI may be for a dependency hosted elsewhere.
      # Unfortunately as a consequence, urls pointing to Azure DevOps Server will not work.
      # Only alternative is to remove the addition of ".git" suffix since the other providers
      # (GitHub, GitLab, BitBucket) work with or without the suffix.
      # That change has other ramifications, so it'd be better if Azure started supporting ".git"
      # like all the other providers.
      uri = SharedHelpers.scp_to_standard(uri)
      uri = URI(uri)
      hostname = uri.hostname.to_s
      hostname == "dev.azure.com" || hostname.end_with?(".visualstudio.com")
    end

    # Add in username and password if present in credentials.
    # Credentials are never present for production Dependabot.
    sig { params(uri: String).returns(String) }
    def uri_with_auth(uri)
      uri = SharedHelpers.scp_to_standard(uri)
      uri = URI(uri)
      cred = credentials.select { |c| c["type"] == "git_source" }
                        .find { |c| uri.host == c["host"] }

      uri.scheme = "https" if uri.scheme != "http"

      if !uri.password && cred && cred.fetch("username", nil) && cred.fetch("password", nil)
        # URI doesn't have authentication details, but we have credentials
        uri.user = URI.encode_www_form_component(cred["username"])
        uri.password = URI.encode_www_form_component(cred["password"])
      end

      uri.to_s
    end

    sig { params(line: String).returns(String) }
    def sha_for_update_pack_line(line)
      T.must(line.split.first).chars.last(40).join
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def excon_defaults
      # Some git hosts are slow when returning a large number of tags
      SharedHelpers.excon_defaults(read_timeout: 20)
    end
  end
end
