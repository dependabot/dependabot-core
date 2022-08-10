# frozen_string_literal: true

require "functions/conflicting_dependency_resolver"
require "functions/dependency_source"
require "functions/file_parser"
require "functions/force_updater"
require "functions/lockfile_updater"
require "functions/version_resolver"

module Functions
  class NotImplementedError < StandardError; end

  def self.parsed_gemfile(**args)
    set_bundler_flags_and_credentials(dir: args.fetch(:dir), credentials: [])
    FileParser.new(lockfile_name: args.fetch(:lockfile_name)).
      parsed_gemfile(gemfile_name: args.fetch(:gemfile_name))
  end

  def self.parsed_gemspec(**args)
    set_bundler_flags_and_credentials(dir: args.fetch(:dir), credentials: [])
    FileParser.new(lockfile_name: args.fetch(:lockfile_name)).
      parsed_gemspec(gemspec_name: args.fetch(:gemspec_name))
  end

  def self.vendor_cache_dir(**args)
    set_bundler_flags_and_credentials(dir: args.fetch(:dir), credentials: [])
    Bundler.app_cache
  end

  def self.update_lockfile(**args)
    set_bundler_flags_and_credentials(dir: args.fetch(:dir), credentials: args.fetch(:credentials))
    LockfileUpdater.new(
      gemfile_name: args.fetch(:gemfile_name),
      lockfile_name: args.fetch(:lockfile_name),
      dependencies: args.fetch(:dependencies)
    ).run
  end

  def self.force_update(**args)
    set_bundler_flags_and_credentials(dir: args.fetch(:dir), credentials: args.fetch(:credentials))
    ForceUpdater.new(
      dependency_name: args.fetch(:dependency_name),
      target_version: args.fetch(:target_version),
      gemfile_name: args.fetch(:gemfile_name),
      lockfile_name: args.fetch(:lockfile_name),
      update_multiple_dependencies: args.fetch(:update_multiple_dependencies)
    ).run
  end

  def self.dependency_source_type(**args)
    set_bundler_flags_and_credentials(dir: args.fetch(:dir), credentials: args.fetch(:credentials))

    DependencySource.new(
      gemfile_name: args.fetch(:gemfile_name),
      dependency_name: args.fetch(:dependency_name)
    ).type
  end

  def self.depencency_source_latest_git_version(**args)
    set_bundler_flags_and_credentials(dir: args.fetch(:dir), credentials: args.fetch(:credentials))
    DependencySource.new(
      gemfile_name: args.fetch(:gemfile_name),
      dependency_name: args.fetch(:dependency_name)
    ).latest_git_version(
      dependency_source_url: args.fetch(:dependency_source_url),
      dependency_source_branch: args.fetch(:dependency_source_branch)
    )
  end

  def self.private_registry_versions(**args)
    set_bundler_flags_and_credentials(dir: args.fetch(:dir), credentials: args.fetch(:credentials))

    DependencySource.new(
      gemfile_name: args.fetch(:gemfile_name),
      dependency_name: args.fetch(:dependency_name)
    ).private_registry_versions
  end

  def self.resolve_version(**args)
    set_bundler_flags_and_credentials(dir: args.fetch(:dir), credentials: args.fetch(:credentials))
    VersionResolver.new(
      dependency_name: args.fetch(:dependency_name),
      dependency_requirements: args.fetch(:dependency_requirements),
      gemfile_name: args.fetch(:gemfile_name),
      lockfile_name: args.fetch(:lockfile_name)
    ).version_details
  end

  def self.jfrog_source(**args)
    # Set flags and credentials
    set_bundler_flags_and_credentials(dir: args.fetch(:dir), credentials: args.fetch(:credentials))

    Bundler::Definition.build(args.fetch(:gemfile_name), nil, {}).
      send(:sources).
      rubygems_remotes.
      find { |uri| uri.host.include?("jfrog") }&.
      host
  end

  def self.git_specs(**args)
    set_bundler_flags_and_credentials(dir: args.fetch(:dir), credentials: args.fetch(:credentials))

    git_specs = Bundler::Definition.build(args.fetch(:gemfile_name), nil, {}).dependencies.
                select do |spec|
      spec.source.is_a?(Bundler::Source::Git)
    end
    git_specs.map do |spec|
      # Piggy-back off some private Bundler methods to configure the
      # URI with auth details in the same way Bundler does.
      git_proxy = spec.source.send(:git_proxy)
      auth_uri = spec.source.uri.gsub("git://", "https://")
      auth_uri = git_proxy.send(:configured_uri_for, auth_uri)
      auth_uri += ".git" unless auth_uri.end_with?(".git")
      auth_uri += "/info/refs?service=git-upload-pack"
      {
        uri: spec.source.uri,
        auth_uri: auth_uri
      }
    end
  end

  def self.conflicting_dependencies(**args)
    set_bundler_flags_and_credentials(dir: args.fetch(:dir), credentials: args.fetch(:credentials))
    ConflictingDependencyResolver.new(
      dependency_name: args.fetch(:dependency_name),
      target_version: args.fetch(:target_version),
      lockfile_name: args.fetch(:lockfile_name)
    ).conflicting_dependencies
  end

  def self.set_bundler_flags_and_credentials(dir:, credentials:)
    dir = dir ? Pathname.new(dir) : dir
    Bundler.instance_variable_set(:@root, dir)

    # Remove installed gems from the default Rubygems index
    Gem::Specification.all =
      Gem::Specification.send(:default_stubs, "*.gemspec")

    # Set auth details
    relevant_credentials(credentials).each do |cred|
      token = cred["token"] ||
              "#{cred['username']}:#{cred['password']}"

      Bundler.settings.set_command_option(
        cred.fetch("host"),
        token.gsub("@", "%40").gsub("?", "%3F")
      )
    end

    # NOTE: Prevent bundler from printing resolution information
    Bundler.ui = Bundler::UI::Silent.new

    Bundler.settings.set_command_option("forget_cli_options", "true")
  end

  def self.relevant_credentials(credentials)
    [
      *git_source_credentials(credentials),
      *private_registry_credentials(credentials)
    ].select { |cred| cred["password"] || cred["token"] }
  end

  def self.private_registry_credentials(credentials)
    credentials.
      select { |cred| cred["type"] == "rubygems_server" }
  end

  def self.git_source_credentials(credentials)
    credentials.
      select { |cred| cred["type"] == "git_source" }
  end
end
