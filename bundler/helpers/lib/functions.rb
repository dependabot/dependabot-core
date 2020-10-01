require "functions/file_parser"
require "functions/force_updater"
require "functions/lockfile_updater"
require "functions/dependency_source"

module Functions
  def self.parsed_gemfile(lockfile_name:, gemfile_name:, dir:)
    FileParser.new(dir: dir, lockfile_name: lockfile_name).
      parsed_gemfile(gemfile_name: gemfile_name)
  end

  def self.parsed_gemspec(lockfile_name:, gemspec_name:, dir:)
    FileParser.new(dir: dir, lockfile_name: lockfile_name).
      parsed_gemspec(gemspec_name: gemspec_name)
  end

  def self.vendor_cache_dir(dir:)
    # Set the path for path gemspec correctly
    Bundler.instance_variable_set(:@root, dir)
    Bundler.app_cache
  end

  def self.update_lockfile(dir:, gemfile_name:, lockfile_name:, using_bundler_2:,
                           credentials:, dependencies:)
    LockfileUpdater.new(
      dir: dir,
      gemfile_name: gemfile_name,
      lockfile_name: lockfile_name,
      using_bundler_2: using_bundler_2,
      credentials: credentials,
      dependencies: dependencies,
    ).run
  end

  def self.force_update(dir:, dependency_name:, target_version:, gemfile_name:,
                        lockfile_name:, using_bundler_2:, credentials:,
                        update_multiple_dependencies:)
    ForceUpdater.new(
      dir: dir,
      dependency_name: dependency_name,
      target_version: target_version,
      gemfile_name: gemfile_name,
      lockfile_name: lockfile_name,
      using_bundler_2: using_bundler_2,
      credentials: credentials,
      update_multiple_dependencies: update_multiple_dependencies,
    ).run
  end

  def self.dependency_source_type(gemfile_name:, dependency_name:, dir:,
                                  credentials:)
    DependencySource.new(
      gemfile_name: gemfile_name,
      dependency_name: dependency_name,
      dir: dir,
      credentials: credentials
    ).type
  end
end
