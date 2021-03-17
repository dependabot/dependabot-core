module Functions
  class NotImplementedError < StandardError; end

  def self.parsed_gemfile(lockfile_name:, gemfile_name:, dir:)
    raise NotImplementedError, "Bundler 2 adapter does not yet implement #{__method__}"
  end

  def self.parsed_gemspec(lockfile_name:, gemspec_name:, dir:)
    raise NotImplementedError, "Bundler 2 adapter does not yet implement #{__method__}"
  end

  def self.vendor_cache_dir(dir:)
    raise NotImplementedError, "Bundler 2 adapter does not yet implement #{__method__}"
  end

  def self.update_lockfile(dir:, gemfile_name:, lockfile_name:, using_bundler2:,
                           credentials:, dependencies:)
    raise NotImplementedError, "Bundler 2 adapter does not yet implement #{__method__}"
  end

  def self.force_update(dir:, dependency_name:, target_version:, gemfile_name:,
                        lockfile_name:, using_bundler2:, credentials:,
                        update_multiple_dependencies:)
    raise NotImplementedError, "Bundler 2 adapter does not yet implement #{__method__}"
  end

  def self.dependency_source_type(gemfile_name:, dependency_name:, dir:,
                                  credentials:)
    raise NotImplementedError, "Bundler 2 adapter does not yet implement #{__method__}"
  end

  def self.depencency_source_latest_git_version(gemfile_name:, dependency_name:,
                                                dir:, credentials:,
                                                dependency_source_url:,
                                                dependency_source_branch:)
    raise NotImplementedError, "Bundler 2 adapter does not yet implement #{__method__}"
  end

  def self.private_registry_versions(gemfile_name:, dependency_name:, dir:,
                                     credentials:)
    raise NotImplementedError, "Bundler 2 adapter does not yet implement #{__method__}"
  end

  def self.resolve_version(dependency_name:, dependency_requirements:,
                           gemfile_name:, lockfile_name:, using_bundler2:,
                           dir:, credentials:)
    raise NotImplementedError, "Bundler 2 adapter does not yet implement #{__method__}"
  end

  def self.jfrog_source(dir:, gemfile_name:, credentials:, using_bundler2:)
    raise NotImplementedError, "Bundler 2 adapter does not yet implement #{__method__}"
  end

  def self.git_specs(dir:, gemfile_name:, credentials:, using_bundler2:)
    raise NotImplementedError, "Bundler 2 adapter does not yet implement #{__method__}"
  end

  def self.set_bundler_flags_and_credentials(dir:, credentials:,
                                             using_bundler2:)
    raise NotImplementedError, "Bundler 2 adapter does not yet implement #{__method__}"
  end

  def self.conflicting_dependencies(dir:, dependency_name:, target_version:,
                                    lockfile_name:, using_bundler2:, credentials:)
    raise NotImplementedError, "Bundler 2 adapter does not yet implement #{__method__}"
  end
end
