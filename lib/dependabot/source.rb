# frozen_string_literal: true

module Dependabot
  class Source
    SOURCE_REGEX = %r{
      (?<provider>github(?=\.com)|bitbucket(?=\.org)|gitlab(?=\.com))
      (?:\.com|\.org)[/:]
      (?<repo>[^/\s]+/(?:(?!\.git|.\s)[^/\s#"',])+)
      (?:(?:/tree|/blob|/src)/master/(?<directory>.*)[\#|/])?
    }x

    attr_reader :provider, :repo, :directory, :api_endpoint

    def self.from_url(url_string)
      return unless url_string&.match?(SOURCE_REGEX)

      captures = url_string.match(SOURCE_REGEX).named_captures

      new(
        provider: captures.fetch("provider"),
        repo: captures.fetch("repo"),
        directory: captures.fetch("directory")
      )
    end

    def initialize(provider:, repo:, directory: nil, api_endpoint: nil)
      @provider = provider
      @repo = repo
      @directory = directory
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

    def default_api_endpoint(provider)
      case provider
      when "github" then "https://api.github.com/"
      when "bitbucket" then "https://api.bitbucket.org/2.0/"
      when "gitlab" then "https://gitlab.com/api/v4/"
      else raise "Unexpected provider '#{provider}'"
      end
    end
  end
end
