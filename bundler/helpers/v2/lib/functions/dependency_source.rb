# frozen_string_literal: true

module Functions
  class DependencySource
    attr_reader :gemfile_name, :dependency_name

    RUBYGEMS = "rubygems"
    PRIVATE_REGISTRY = "private"
    GIT = "git"
    OTHER = "other"

    def initialize(gemfile_name:, dependency_name:)
      @gemfile_name = gemfile_name
      @dependency_name = dependency_name
    end

    def type
      bundler_source = specified_source || default_source
      type_of(bundler_source)
    end

    def latest_git_version(dependency_source_url:, dependency_source_branch:)
      source = Bundler::Source::Git.new(
        "uri" => dependency_source_url,
        "branch" => dependency_source_branch,
        "name" => dependency_name,
        "submodules" => true
      )

      # Tell Bundler we're fine with fetching the source remotely
      source.instance_variable_set(:@allow_remote, true)

      spec = source.specs.first
      { version: spec.version, commit_sha: spec.source.revision }
    end

    def private_registry_versions
      bundler_source = specified_source || default_source

      bundler_source.
        fetchers.flat_map do |fetcher|
          fetcher.
            specs([dependency_name], bundler_source).
            search_all(dependency_name)
        end.
        map(&:version)
    end

    private

    def type_of(bundler_source)
      case bundler_source
      when Bundler::Source::Rubygems
        remote = bundler_source.remotes.first
        if remote.nil? || remote.to_s == "https://rubygems.org/"
          RUBYGEMS
        else
          PRIVATE_REGISTRY
        end
      when Bundler::Source::Git
        GIT
      else
        OTHER
      end
    end

    def specified_source
      return @specified_source if defined? @specified_source

      @specified_source = definition.dependencies.
                          find { |dep| dep.name == dependency_name }&.source
    end

    def default_source
      definition.send(:sources).default_source
    end

    def definition
      @definition ||= Bundler::Definition.build(gemfile_name, nil, {})
    end

    def serialize_bundler_source(source)
      {
        type: source.class.to_s
      }
    end
  end
end
