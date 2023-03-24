# frozen_string_literal: true

require "fileutils"

module Functions
  class LockfileUpdater
    RETRYABLE_ERRORS = [Bundler::HTTPError].freeze
    GEM_NOT_FOUND_ERROR_REGEX =
      /
        locked\sto\s(?<name>[^\s]+)\s\(|
        not\sfind\s(?<name>[^\s]+)-\d|
        has\s(?<name>[^\s]+)\slocked\sat
      /x
    DEPENDENCY_DROPPED = "_dependency_dropped_"

    def initialize(gemfile_name:, lockfile_name:, dependencies:)
      @gemfile_name = gemfile_name
      @lockfile_name = lockfile_name
      @dependencies = dependencies
    end

    def run
      generate_lockfile
    end

    private

    attr_reader :gemfile_name, :lockfile_name, :dependencies

    def generate_lockfile # rubocop:disable Metrics/PerceivedComplexity
      dependencies_to_unlock = dependencies.map { |d| d.fetch("name") }

      begin
        definition = build_definition(dependencies_to_unlock)

        old_reqs = lock_deps_being_updated_to_exact_versions(definition)

        definition.resolve_remotely!

        old_reqs.each do |dep_name, old_req|
          d_dep = definition.dependencies.find { |d| d.name == dep_name }
          if old_req.to_s == DEPENDENCY_DROPPED then definition.dependencies.delete(d_dep)
          else
            d_dep.instance_variable_set(:@requirement, old_req)
          end
        end

        cache_vendored_gems(definition) if Bundler.app_cache.exist?

        definition.to_lock
      rescue Bundler::GemNotFound => e
        unlock_yanked_gem(dependencies_to_unlock, e) && retry
      rescue Bundler::SolveFailure => e
        unlock_blocking_subdeps(dependencies_to_unlock, e) && retry
      rescue *RETRYABLE_ERRORS
        raise if @retrying

        @retrying = true
        sleep(rand(1.0..5.0))
        retry
      end
    end

    def cache_vendored_gems(definition)
      # Dependencies that have been unlocked for the update (including
      # sub-dependencies)
      unlocked_gems = definition.instance_variable_get(:@unlock).
                      fetch(:gems).reject { |gem| __keep_on_prune?(gem) }
      bundler_opts = {
        cache_all: true,
        cache_all_platforms: true,
        no_prune: true
      }

      Bundler.settings.temporary(**bundler_opts) do
        # Fetch and cache gems on all platforms without pruning
        Bundler::Runtime.new(nil, definition).cache

        # Only prune unlocked gems (the original implementation is in
        # Bundler::Runtime)
        cache_path = Bundler.app_cache
        resolve = definition.resolve
        prune_gem_cache(resolve, cache_path, unlocked_gems)
        prune_git_and_path_cache(resolve, cache_path)
      end
    end

    # This is not officially supported and may be removed without notice.
    def __keep_on_prune?(spec_name)
      unless (specs = Bundler.settings[:persistent_gems_after_clean])
        return false
      end

      specs.include?(spec_name)
    end

    # Copied from Bundler::Runtime: Modified to only prune gems that have
    # been unlocked
    def prune_gem_cache(resolve, cache_path, unlocked_gems)
      cached_gems = Dir["#{cache_path}/*.gem"]

      outdated_gems = cached_gems.reject do |path|
        spec = Bundler.rubygems.spec_from_gem path

        !unlocked_gems.include?(spec.name) || resolve.any? do |s|
          s.name == spec.name && s.version == spec.version &&
            !s.source.is_a?(Bundler::Source::Git)
        end
      end

      return unless outdated_gems.any?

      outdated_gems.each do |path|
        File.delete(path)
      end
    end

    # Copied from Bundler::Runtime
    def prune_git_and_path_cache(resolve, cache_path)
      cached_git_and_path = Dir["#{cache_path}/*/.bundlecache"]

      outdated_git_and_path = cached_git_and_path.reject do |path|
        name = File.basename(File.dirname(path))

        resolve.any? do |s|
          s.source.respond_to?(:app_cache_dirname) &&
            s.source.app_cache_dirname == name
        end
      end

      return unless outdated_git_and_path.any?

      outdated_git_and_path.each do |path|
        path = File.dirname(path)
        FileUtils.rm_rf(path)
      end
    end

    def unlock_yanked_gem(dependencies_to_unlock, error)
      raise unless error.message.match?(GEM_NOT_FOUND_ERROR_REGEX)

      gem_name = error.message.match(GEM_NOT_FOUND_ERROR_REGEX).
                 named_captures["name"]
      raise if dependencies_to_unlock.include?(gem_name)

      dependencies_to_unlock << gem_name
    end

    def unlock_blocking_subdeps(dependencies_to_unlock, error)
      all_deps =  Bundler::LockfileParser.new(lockfile).
                  specs.map(&:name).map(&:to_s)
      top_level = build_definition([]).dependencies.
                  map(&:name).map(&:to_s)
      allowed_new_unlocks = all_deps - top_level - dependencies_to_unlock

      raise if allowed_new_unlocks.none?

      # Unlock any sub-dependencies that Bundler reports caused the
      # conflict
      incompatibility = error.cause.incompatibility
      potential_deps = []

      while incompatibility.conflict?
        cause = incompatibility.cause
        incompatibility = cause.incompatibility

        incompatibility.terms.each do |term|
          name = term.package.name
          potential_deps << name if allowed_new_unlocks.include?(name)
        end
      end

      # If there are specific dependencies we can unlock, unlock them
      return dependencies_to_unlock.append(*potentials_deps) if potentials_deps.any?

      # Fall back to unlocking *all* sub-dependencies. This is required
      # because Bundler's SolveFailure objects don't include enough
      # information to chart the full path through all conflicts unwound
      dependencies_to_unlock.append(*allowed_new_unlocks)
    end

    def build_definition(dependencies_to_unlock)
      defn = Bundler::Definition.build(
        gemfile_name,
        lockfile_name,
        gems: dependencies_to_unlock
      )

      # Bundler unlocks the sub-dependencies of gems it is passed even
      # if those sub-deps are top-level dependencies. We only want true
      # subdeps unlocked, like they were in the UpdateChecker, so we
      # mutate the unlocked gems array.
      unlocked = defn.instance_variable_get(:@unlock).fetch(:gems)
      must_not_unlock = defn.dependencies.map(&:name).map(&:to_s) -
                        dependencies_to_unlock
      unlocked.reject! { |n| must_not_unlock.include?(n) }

      defn
    end

    def lock_deps_being_updated_to_exact_versions(definition)
      dependencies.each_with_object({}) do |dep, old_reqs|
        defn_dep = definition.dependencies.find do |d|
          d.name == dep.fetch("name")
        end

        if defn_dep.nil?
          definition.dependencies <<
            Bundler::Dependency.new(dep.fetch("name"), dep.fetch("version"))
          old_reqs[dep.fetch("name")] = DEPENDENCY_DROPPED
        elsif git_dependency?(dep) &&
              defn_dep.source.is_a?(Bundler::Source::Git)
          defn_dep.source.unlock!
        elsif Gem::Version.correct?(dep.fetch("version"))
          new_req = Gem::Requirement.create("= #{dep.fetch('version')}")
          old_reqs[dep.fetch("name")] = defn_dep.requirement
          defn_dep.instance_variable_set(:@requirement, new_req)
        end
      end
    end

    def git_dependency?(dep)
      sources = dep.fetch("requirements").map { |r| r.fetch("source") }
      sources.all? { |s| s&.fetch("type", nil) == "git" }
    end

    def lockfile
      @lockfile ||= File.read(lockfile_name)
    end
  end
end
