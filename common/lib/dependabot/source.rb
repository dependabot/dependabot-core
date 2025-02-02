# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class Source
    extend T::Sig

    GITHUB_SOURCE = %r{
      (?<provider>github)
      (?:\.com)[/:]
      (?<repo>[\w.-]+/(?:[\w.-])+)
      (?:(?:/tree|/blob)/(?<branch>[^/]+)/(?<directory>.*)[\#|/])?
    }x

    GITHUB_ENTERPRISE_SOURCE = %r{
      (?<protocol>(http://|https://|git://|ssh://))*
      (?<username>[^@]+@)*
      (?<host>[^/]+)
      [/:]
      (?<repo>[\w.-]+/(?:[\w.-])+)
      (?:(?:/tree|/blob)/(?<branch>[^/]+)/(?<directory>.*)[\#|/])?
    }x

    GITLAB_SOURCE = %r{
      (?<provider>gitlab)
      (?:\.com)[/:]
      (?<repo>[^/]+/(?:[^/])+((?!/tree|/blob/|/-)/[^/]+)?)
      (?:(?:/tree|/blob)/(?<branch>[^/]+)/(?<directory>.*)[\#|/].*)?
    }x

    BITBUCKET_SOURCE = %r{
      (?<provider>bitbucket)
      (?:\.org)[/:]
      (?<repo>[\w.-]+/(?:[\w.-])+)
      (?:(?:/src)/(?<branch>[^/]+)/(?<directory>.*)[\#|/])?
    }x

    AZURE_SOURCE = %r{
      (?<provider>azure)
      (?:\.com)[/:]
      (?<repo>[\w.-]+/([\w.-]+/)?(?:_git/)(?:[\w.-])+)
    }x

    CODECOMMIT_SOURCE = %r{
      (?<protocol>(http://|https://|git://|ssh://))
      git[-]
      (?<provider>codecommit)
      (?:.*)
      (?:\.com/v1/repos/)
      (?<repo>([^/]*))
      (?:/)?(?<directory>[^?]*)?
      [?]?
      (?<ref>.*)?
    }x

    SOURCE_REGEX = /
      (?:#{GITHUB_SOURCE})|
      (?:#{GITLAB_SOURCE})|
      (?:#{BITBUCKET_SOURCE})|
      (?:#{AZURE_SOURCE})|
      (?:#{CODECOMMIT_SOURCE})
    /x

    IGNORED_PROVIDER_HOSTS = T.let(%w(gitbox.apache.org svn.apache.org fuchsia.googlesource.com).freeze,
                                   T::Array[String])

    sig { returns(String) }
    attr_accessor :provider

    sig { returns(String) }
    attr_accessor :repo

    sig { returns(T.nilable(String)) }
    attr_accessor :directory

    sig { returns(T.nilable(T::Array[String])) }
    attr_accessor :directories

    sig { returns(T.nilable(String)) }
    attr_accessor :branch

    sig { returns(T.nilable(String)) }
    attr_accessor :commit

    sig { returns(String) }
    attr_accessor :hostname

    sig { returns(T.nilable(String)) }
    attr_accessor :api_endpoint

    sig { params(url_string: T.nilable(String)).returns(T.nilable(Source)) }
    def self.from_url(url_string)
      return github_enterprise_from_url(url_string) unless url_string&.match?(SOURCE_REGEX)

      captures = T.must(url_string.match(SOURCE_REGEX)).named_captures

      new(
        provider: T.must(captures.fetch("provider")),
        repo: T.must(captures.fetch("repo")).delete_suffix(".git").delete_suffix("."),
        directory: captures.fetch("directory"),
        branch: captures.fetch("branch")
      )
    end

    sig { params(url_string: T.nilable(String)).returns(T.nilable(Source)) }
    def self.github_enterprise_from_url(url_string)
      captures = url_string&.match(GITHUB_ENTERPRISE_SOURCE)&.named_captures
      return unless captures
      return if IGNORED_PROVIDER_HOSTS.include?(captures.fetch("host"))

      base_url = "https://#{captures.fetch('host')}"

      return unless github_enterprise?(base_url)

      new(
        provider: "github",
        repo: T.must(captures.fetch("repo")).delete_suffix(".git").delete_suffix("."),
        directory: captures.fetch("directory"),
        branch: captures.fetch("branch"),
        hostname: captures.fetch("host"),
        api_endpoint: File.join(base_url, "api", "v3")
      )
    end

    sig { params(base_url: String).returns(T::Boolean) }
    def self.github_enterprise?(base_url)
      resp = Excon.get(File.join(base_url, "status"))
      resp.status == 200 &&
        # Alternatively: resp.headers["Server"] == "GitHub.com", but this
        # currently doesn't work with development environments
        ((resp.headers["X-GitHub-Request-Id"] && !resp.headers["X-GitHub-Request-Id"]&.empty?) || false)
    rescue StandardError
      false
    end

    sig do
      params(
        provider: String,
        repo: String,
        directory: T.nilable(String),
        directories: T.nilable(T::Array[String]),
        branch: T.nilable(String),
        commit: T.nilable(String),
        hostname: T.nilable(String),
        api_endpoint: T.nilable(String)
      ).void
    end
    def initialize(provider:, repo:, directory: nil, directories: nil, branch: nil, commit: nil,
                   hostname: nil, api_endpoint: nil)
      if (hostname.nil? ^ api_endpoint.nil?) && (provider != "codecommit")
        msg = "Both hostname and api_endpoint must be specified if either " \
              "are. Alternatively, both may be left blank to use the " \
              "provider's defaults."
        raise msg
      end

      @provider = provider
      @repo = repo
      @directory = directory
      @directories = directories
      @branch = branch
      @commit = commit
      @hostname = T.let(hostname || default_hostname(provider), String)
      @api_endpoint = T.let(api_endpoint || default_api_endpoint(provider), T.nilable(String))
    end

    sig { returns(String) }
    def url
      "https://" + hostname + "/" + repo
    end

    sig { returns(String) }
    def url_with_directory
      return url if [nil, ".", "/"].include?(directory)

      case provider
      when "github", "gitlab"
        path = Pathname.new(File.join("tree/#{branch || 'HEAD'}", directory))
                       .cleanpath.to_path
        url + "/" + path
      when "bitbucket"
        path = Pathname.new(File.join("src/#{branch || 'default'}", directory))
                       .cleanpath.to_path
        url + "/" + path
      when "azure"
        url + "?path=#{directory}"
      when "codecommit"
        raise "The codecommit provider does not utilize URLs"
      else raise "Unexpected repo provider '#{provider}'"
      end
    end

    sig { returns(String) }
    def organization
      T.must(repo.split("/").first)
    end

    sig { returns(String) }
    def project
      raise "Project is an Azure DevOps concept only" unless provider == "azure"

      parts = repo.split("/_git/")
      return T.must(T.must(parts.first).split("/").last) if parts.first&.split("/")&.count == 2

      T.must(parts.last)
    end

    sig { returns(String) }
    def unscoped_repo
      T.must(repo.split("/").last)
    end

    private

    sig { params(provider: String).returns(String) }
    def default_hostname(provider)
      case provider
      when "github" then "github.com"
      when "bitbucket" then "bitbucket.org"
      when "gitlab" then "gitlab.com"
      when "azure" then "dev.azure.com"
      when "codecommit" then "us-east-1"
      else raise "Unexpected provider '#{provider}'"
      end
    end

    sig { params(provider: String).returns(T.nilable(String)) }
    def default_api_endpoint(provider)
      case provider
      when "github" then "https://api.github.com/"
      when "bitbucket" then "https://api.bitbucket.org/2.0/"
      when "gitlab" then "https://gitlab.com/api/v4"
      when "azure" then "https://dev.azure.com/"
      when "codecommit" then nil
      else raise "Unexpected provider '#{provider}'"
      end
    end
  end
end
