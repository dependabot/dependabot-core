# frozen_string_literal: true

require "dependabot/provider/bitbucket"
require "dependabot/provider/github"
require "dependabot/provider/gitlab"

module Dependabot
  class Source
    SOURCE_REGEX = %r{
      (?<provider>github(?=\.com)|bitbucket(?=\.org)|gitlab(?=\.com))
      (?:\.com|\.org)[/:]
      (?<repo>[^/\s]+/(?:(?!\.git|\.\s)[^/\s#"',])+)
      (?:(?:/tree|/blob|/src)/(?<branch>[^/]+)/(?<directory>.*)[\#|/])?
    }x

    attr_reader :provider, :repo, :directory,
                :branch, :hostname, :api_endpoint, :url

    def self.from_url(url_string)
      return unless url_string&.match?(SOURCE_REGEX)

      captures = url_string.match(SOURCE_REGEX).named_captures

      new(
        provider: captures.fetch("provider"),
        repo: captures.fetch("repo"),
        directory: captures.fetch("directory"),
        branch: captures.fetch("branch")
      )
    end

    def initialize(provider:, repo:, directory: nil, branch: nil, hostname: nil,
                   api_endpoint: nil)
      if hostname.nil? ^ api_endpoint.nil?
        msg = "Both hostname and api_endpoint must be specified if either "\
              "are. Alternatively, both may be left blank to use the "\
              "provider's defaults."
        raise msg
      end

      provider_default = default_provider(provider).new

      @provider = provider
      @repo = repo
      @directory = directory
      @branch = branch
      @hostname = hostname || provider_default.hostname
      @api_endpoint = api_endpoint || provider_default.api_endpoint
      @url = provider_default.url + repo
    end

    private

    def default_provider(provider)
      case provider
      when "bitbucket" then Dependabot::Provider::BitBucket
      when "github" then Dependabot::Provider::Github
      when "gitlab" then Dependabot::Provider::Gitlab
      else raise "Unexpected provider '#{provider}'"
      end
    end
  end
end
