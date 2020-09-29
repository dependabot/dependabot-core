require "functions/lockfile_updater"
require "functions/file_parser"

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

  def self.update_lockfile(gemfile_name:, lockfile_name:, using_bundler_2:,
                           dir:, credentials:, dependencies:)
    LockfileUpdater.new(
      gemfile_name: gemfile_name,
      lockfile_name: lockfile_name,
      using_bundler_2: using_bundler_2,
      dir: dir,
      credentials: credentials,
      dependencies: dependencies,
    ).run
  end
end
