# frozen_string_literal: true

module Dependabot
  class Source
    attr_accessor :provider, :repo, :directory, :branch, :commit,
                  :hostname, :api_endpoint

    GITHUB_SOURCE = %r{
      (?<provider>github)
      (?:\.com)[/:]
      (?<repo>[\w.-]+/(?:(?!\.git|\.\s)[\w.-])+)
      (?:(?:/tree|/blob)/(?<branch>[^/]+)/(?<directory>.*)[\#|/])?
    }x.freeze

    GITLAB_SOURCE = %r{
      (?<provider>gitlab)
      (?:\.com)[/:]
      (?<repo>[\w.-]+/(?:(?!\.git|\.\s)[\w.-])+)
      (?:(?:/tree|/blob)/(?<branch>[^/]+)/(?<directory>.*)[\#|/])?
    }x.freeze

    BITBUCKET_SOURCE = %r{
      (?<provider>bitbucket)
      (?:\.org)[/:]
      (?<repo>[\w.-]+/(?:(?!\.git|\.\s)[\w.-])+)
      (?:(?:/src)/(?<branch>[^/]+)/(?<directory>.*)[\#|/])?
    }x.freeze

    AZURE_SOURCE = %r{
      (?<provider>azure)
      (?:\.com)[/:]
      (?<repo>[\w.-]+/([\w.-]+/)?(?:_git/)(?:(?!\.git|\.\s)[\w.-])+)
    }x.freeze

    DEFAULT_SOURCE_REGEXS = [
      GITHUB_SOURCE,
      GITLAB_SOURCE,
      BITBUCKET_SOURCE,
      AZURE_SOURCE
    ].freeze

    @registered_sources = []

    # `register_source` is a class method that allows registration
    # of a URL regex with a factory function to create a new
    # `Source` instance from the regex captures.
    def self.register_source(regex, source_factory)
      @registered_sources.push(regex: regex, factory: source_factory)
    end

    # Initialize the default sources.
    # Apps can add to this list via Dependabot::Source.add_source(...).
    DEFAULT_SOURCE_REGEXS.each do |regex|
      Source.register_source(regex, lambda { |captures|
        new(
          provider: captures.fetch("provider"),
          repo: captures["repo"],
          directory: captures["directory"],
          branch: captures["branch"]
        )
      })
    end

    def self.from_url(url_string)
      return unless url_string

      @registered_sources.each do |source_info|
        m = url_string.match(source_info[:regex])
        return source_info[:factory].call(m.named_captures) if m
      end
      puts "Source.from_url failed to find source for: #{url_string}"
    end

    def initialize(provider:, repo:, directory: nil, branch: nil, commit: nil,
                   hostname: nil, api_endpoint: nil)
      if (hostname.nil? ^ api_endpoint.nil?) && (provider != "codecommit")
        msg = "Both hostname and api_endpoint must be specified if either "\
              "are. Alternatively, both may be left blank to use the "\
              "provider's defaults."
        raise msg
      end

      @provider = provider
      @repo = repo
      @directory = directory
      @branch = branch
      @commit = commit
      @hostname = hostname || default_hostname(provider)
      @api_endpoint = api_endpoint || default_api_endpoint(provider)
    end

    def url
      "https://" + hostname + "/" + repo
    end

    # rubocop:disable Metrics/CyclomaticComplexity
    def url_with_directory
      return url if [nil, ".", "/"].include?(directory)

      case provider
      when "github", "gitlab"
        path = Pathname.new(File.join("tree/#{branch || 'HEAD'}", directory)).
               cleanpath.to_path
        url + "/" + path
      when "bitbucket"
        path = Pathname.new(File.join("src/#{branch || 'default'}", directory)).
               cleanpath.to_path
        url + "/" + path
      when "azure"
        url + "?path=#{directory}"
      when "codecommit"
        raise "The codecommit provider does not utilize URLs"
      else raise "Unexpected repo provider '#{provider}'"
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity

    def organization
      repo.split("/").first
    end

    def project
      raise "Project is an Azure DevOps concept only" unless provider == "azure"

      parts = repo.split("/_git/")
      return parts.first.split("/").last if parts.first.split("/").count == 2

      parts.last
    end

    def unscoped_repo
      repo.split("/").last
    end

    private

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
