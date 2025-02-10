# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Functions
  class DependencySource
    extend T::Sig

    sig { returns(String) }
    attr_reader :gemfile_name

    sig { returns(String) }
    attr_reader :dependency_name

    RUBYGEMS = "rubygems"
    PRIVATE_REGISTRY = "private"
    GIT = "git"
    OTHER = "other"

    sig { params(gemfile_name: String, dependency_name: String).void }
    def initialize(gemfile_name:, dependency_name:)
      @gemfile_name = gemfile_name
      @dependency_name = dependency_name
    end

    sig { returns(String) }
    def type
      bundler_source = specified_source || default_source
      type_of(bundler_source)
    end

    sig do
      params(dependency_source_url: String, dependency_source_branch: String)
        .returns(T::Hash[Symbol, String])
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

    sig { returns(T::Array[Bundler::Version]) }
    def private_registry_versions
      bundler_source = specified_source || default_source

      bundler_source
        .fetchers.flat_map do |fetcher|
          fetcher
            .specs([dependency_name], bundler_source)
            .search_all(dependency_name).map(&:version)
        end
    end

    private

    sig { params(bundler_source: Bundler::Source).returns(String) }
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

    sig { returns(T.nilable(Bundler::Source)) }
    def specified_source
      return @specified_source if defined? @specified_source

      @specified_source = definition.dependencies
                                    .find { |dep| dep.name == dependency_name }&.source
    end

    sig { returns(Bundler::Source) }
    def default_source
      definition.send(:sources).default_source
    end

    sig { returns(Bundler::Definition) }
    def definition
      @definition ||= T.let(
        Bundler::Definition.build(gemfile_name, nil, {}),
        Bundler::Definition
      )
    end
  end
end
