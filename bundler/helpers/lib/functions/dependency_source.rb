module Functions
  class DependencySource
    attr_reader :gemfile_name, :dependency_name, :dir, :credentials

    RUBYGEMS = "rubygems"
    PRIVATE_REGISTRY = "private"
    GIT = "git"
    OTHER = "other"

    def initialize(gemfile_name:, dependency_name:, dir:, credentials:)
      @gemfile_name = gemfile_name
      @dependency_name = dependency_name
      @dir = dir
      @credentials = credentials
    end

    def type
      setup_bundler
      bundler_source = specified_source || default_source
      type_of(bundler_source)
    end

    def latest_git_version(dependency_source_url:, dependency_source_branch:)
      setup_bundler

      source = ::Bundler::Source::Git.new(
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

    private

    def setup_bundler
      ::Bundler.instance_variable_set(:@root, dir)

      # TODO: DRY out this setup with Functions::LockfileUpdater
      credentials.each do |cred|
        token = cred["token"] ||
                "#{cred['username']}:#{cred['password']}"

        ::Bundler.settings.set_command_option(
          cred.fetch("host"),
          token.gsub("@", "%40F").gsub("?", "%3F")
        )
      end
    end

    def type_of(bundler_source)
      case bundler_source
      when ::Bundler::Source::Rubygems
        remote = bundler_source.remotes.first
        if remote.nil? || remote.to_s == "https://rubygems.org/"
          RUBYGEMS
        else
          PRIVATE_REGISTRY
        end
      when ::Bundler::Source::Git
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
      @definition ||= ::Bundler::Definition.build(gemfile_name, nil, {})
    end

    def serialize_bundler_source(source)
      {
        type: source.class.to_s
      }
    end
  end
end
