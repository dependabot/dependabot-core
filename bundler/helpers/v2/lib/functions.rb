# frozen_string_literal: true

require "functions/conflicting_dependency_resolver"
require "functions/dependency_source"
require "functions/file_parser"
require "functions/force_updater"
require "functions/lockfile_updater"
require "functions/version_resolver"

module Functions
  class NotImplementedError < StandardError; end

  def self.parsed_gemfile(lockfile_name:, gemfile_name:, dir:)
    set_bundler_flags_and_credentials(dir: dir, credentials: [],
                                      using_bundler2: false)
    FileParser.new(lockfile_name: lockfile_name).
      parsed_gemfile(gemfile_name: gemfile_name)
  end

  def self.parsed_gemspec(lockfile_name:, gemspec_name:, dir:)
    set_bundler_flags_and_credentials(dir: dir, credentials: [],
                                      using_bundler2: false)
    FileParser.new(lockfile_name: lockfile_name).
      parsed_gemspec(gemspec_name: gemspec_name)
  end

  def self.vendor_cache_dir(dir:)
    set_bundler_flags_and_credentials(dir: dir, credentials: [],
                                      using_bundler2: false)
    Bundler.app_cache
  end

  def self.update_lockfile(dir:, gemfile_name:, lockfile_name:, using_bundler2:,
                           credentials:, dependencies:)
    set_bundler_flags_and_credentials(dir: dir, credentials: credentials,
                                      using_bundler2: using_bundler2)
    LockfileUpdater.new(
      gemfile_name: gemfile_name,
      lockfile_name: lockfile_name,
      dependencies: dependencies
    ).run
  end

  def self.force_update(dir:, dependency_name:, target_version:, gemfile_name:,
                        lockfile_name:, using_bundler2:, credentials:,
                        update_multiple_dependencies:)
    set_bundler_flags_and_credentials(dir: dir, credentials: credentials,
                                      using_bundler2: using_bundler2)
    ForceUpdater.new(
      dependency_name: dependency_name,
      target_version: target_version,
      gemfile_name: gemfile_name,
      lockfile_name: lockfile_name,
      update_multiple_dependencies: update_multiple_dependencies
    ).run
  end

  def self.dependency_source_type(gemfile_name:, dependency_name:, dir:,
                                  credentials:)
    set_bundler_flags_and_credentials(dir: dir, credentials: credentials,
                                      using_bundler2: false)

    DependencySource.new(
      gemfile_name: gemfile_name,
      dependency_name: dependency_name
    ).type
  end

  def self.depencency_source_latest_git_version(gemfile_name:, dependency_name:,
                                                dir:, credentials:,
                                                dependency_source_url:,
                                                dependency_source_branch:)
    set_bundler_flags_and_credentials(dir: dir, credentials: credentials,
                                      using_bundler2: false)
    DependencySource.new(
      gemfile_name: gemfile_name,
      dependency_name: dependency_name
    ).latest_git_version(
      dependency_source_url: dependency_source_url,
      dependency_source_branch: dependency_source_branch
    )
  end

  def self.private_registry_versions(gemfile_name:, dependency_name:, dir:,
                                     credentials:)
    set_bundler_flags_and_credentials(dir: dir, credentials: credentials,
                                      using_bundler2: false)

    DependencySource.new(
      gemfile_name: gemfile_name,
      dependency_name: dependency_name
    ).private_registry_versions
  end

  def self.resolve_version(dependency_name:, dependency_requirements:,
                           gemfile_name:, lockfile_name:, using_bundler2:,
                           dir:, credentials:)
    set_bundler_flags_and_credentials(dir: dir, credentials: credentials, using_bundler2: using_bundler2)
    VersionResolver.new(
      dependency_name: dependency_name,
      dependency_requirements: dependency_requirements,
      gemfile_name: gemfile_name,
      lockfile_name: lockfile_name
    ).version_details
  end

  def self.jfrog_source(dir:, gemfile_name:, credentials:, using_bundler2:)
    set_bundler_flags_and_credentials(dir: dir, credentials: credentials, using_bundler2: using_bundler2)

    Bundler::Definition.build(gemfile_name, nil, {}).
      send(:sources).
      rubygems_remotes.
      find { |uri| uri.host.include?("jfrog") }&.
      host
  end

  def self.git_specs(dir:, gemfile_name:, credentials:, using_bundler2:)
    set_bundler_flags_and_credentials(dir: dir, credentials: credentials,
                                      using_bundler2: using_bundler2)

    git_specs = Bundler::Definition.build(gemfile_name, nil, {}).dependencies.
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

  def self.set_bundler_flags_and_credentials(dir:, credentials:,
                                             using_bundler2:)
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
        token.gsub("@", "%40F").gsub("?", "%3F")
      )
    end

    # NOTE: Prevent bundler from printing resolution information
    Bundler.ui = Bundler::UI::Silent.new

    # Use HTTPS for GitHub if lockfile
    Bundler.settings.set_command_option("forget_cli_options", "true")
    Bundler.settings.set_command_option("github.https", "true")
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

  def self.conflicting_dependencies(dir:, dependency_name:, target_version:,
                                    lockfile_name:, using_bundler2:, credentials:)
    set_bundler_flags_and_credentials(dir: dir, credentials: credentials,
                                      using_bundler2: using_bundler2)
    ConflictingDependencyResolver.new(
      dependency_name: dependency_name,
      target_version: target_version,
      lockfile_name: lockfile_name
    ).conflicting_dependencies
  end
end
