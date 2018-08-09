# frozen_string_literal: true

module Dependabot
  class Source
    SOURCE_REGEX = %r{
      (?<provider>github(?=\.com)|bitbucket(?=\.org)|gitlab(?=\.com))
      (?:\.com|\.org)[/:]
      (?<repo>[^/\s]+/(?:(?!\.git|.\s)[^/\s#"',])+)
      (?:(?:/tree|/blob|/src)/(?<branch>[^/]+)/(?<directory>.*)[\#|/])?
    }x

    attr_reader :provider, :repo, :directory, :branch, :hostname, :api_endpoint

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

      @provider = provider
      @repo = repo
      @directory = directory
      @branch = branch
      @hostname = hostname || default_hostname(provider)
      @api_endpoint = api_endpoint || default_api_endpoint(provider)
    end

    def url
      case provider
      when "github" then "https://github.com/" + repo
      when "bitbucket" then "https://bitbucket.org/" + repo
      when "gitlab" then "https://gitlab.com/" + repo
      else raise "Unexpected repo provider '#{provider}'"
      end
    end

    private

    def default_hostname(provider)
      case provider
      when "github" then "github.com"
      when "bitbucket" then "bitbucket.org"
      when "gitlab" then "gitlab.com"
      else raise "Unexpected provider '#{provider}'"
      end
    end

    def default_api_endpoint(provider)
      case provider
      when "github" then "https://api.github.com/"
      when "bitbucket" then "https://api.bitbucket.org/2.0/"
      when "gitlab" then "https://gitlab.com/api/v4"
      else raise "Unexpected provider '#{provider}'"
      end
    end
  end
end
