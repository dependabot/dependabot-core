# frozen_string_literal: true

module Dependabot
  class Source
    SOURCE_REGEX = %r{
      (?<host>github(?=\.com)|bitbucket(?=\.org)|gitlab(?=\.com))
      (?:\.com|\.org)[/:]
      (?<repo>[^/\s]+/(?:(?!\.git|.\s)[^/\s#"',])+)
      (?:(?:/tree|/blob|/src)/master/(?<directory>.*)[\#|/])?
    }x

    attr_reader :host, :repo, :directory

    def self.from_url(url_string)
      return unless url_string&.match?(SOURCE_REGEX)

      captures = url_string.match(SOURCE_REGEX).named_captures

      new(
        host: captures.fetch("host"),
        repo: captures.fetch("repo"),
        directory: captures.fetch("directory")
      )
    end

    def initialize(host:, repo:, directory: nil)
      @host = host
      @repo = repo
      @directory = directory
    end

    def url
      case host
      when "github" then "https://github.com/" + repo
      when "bitbucket" then "https://bitbucket.org/" + repo
      when "gitlab" then "https://gitlab.com/" + repo
      else raise "Unexpected repo host '#{host}'"
      end
    end
  end
end
