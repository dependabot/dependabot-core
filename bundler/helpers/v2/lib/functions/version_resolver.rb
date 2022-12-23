# frozen_string_literal: true

module Functions
  class VersionResolver
    GEM_NOT_FOUND_ERROR_REGEX = /locked to (?<name>[^\s]+) \(/

    attr_reader :dependency_name, :dependency_requirements,
                :gemfile_name, :lockfile_name

    def initialize(dependency_name:, dependency_requirements:,
                   gemfile_name:, lockfile_name:)
      @dependency_name = dependency_name
      @dependency_requirements = dependency_requirements
      @gemfile_name = gemfile_name
      @lockfile_name = lockfile_name
    end

    def version_details
      # If the dependency is Bundler itself then we can't trust the
      # version that has been returned (it's the version Dependabot is
      # running on, rather than the true latest resolvable version).
      return nil if dependency_name == "bundler"

      dep = dependency_from_definition

      # If the dependency wasn't found in the definition, but *is*
      # included in a gemspec, it's because the Gemfile didn't import
      # the gemspec. This is unusual, but the correct behaviour if/when
      # it happens is to behave as if the repo was gemspec-only.
      return "latest" if dep.nil? && dependency_requirements.any?

      # Otherwise, if the dependency wasn't found it's because it is a
      # subdependency that was removed when attempting to update it.
      return nil if dep.nil?

      details = {
        version: dep.version,
        ruby_version: ruby_version,
        fetcher: fetcher_class(dep)
      }
      details[:commit_sha] = dep.source.revision if dep.source.instance_of?(::Bundler::Source::Git)
      details
    end

    private

    # rubocop:disable Metrics/PerceivedComplexity
    def dependency_from_definition(unlock_subdependencies: true)
      dependencies_to_unlock = [dependency_name]
      dependencies_to_unlock += subdependencies if unlock_subdependencies
      begin
        definition = build_definition(dependencies_to_unlock)
        definition.resolve_remotely!
      rescue ::Bundler::GemNotFound => e
        unlock_yanked_gem(dependencies_to_unlock, e) && retry
      rescue ::Bundler::HTTPError => e
        # Retry network errors
        # Note: in_a_native_bundler_context will also retry `Bundler::HTTPError` errors
        # up to three times meaning we'll end up retrying this error up to six times
        # TODO: Could we get rid of this retry logic and only rely on
        # SharedBundlerHelpers.in_a_native_bundler_context
        attempt ||= 1
        attempt += 1
        raise if attempt > 3 || !e.message.include?("Network error")

        retry
      end

      dep = definition.resolve.find { |d| d.name == dependency_name }
      return dep if dep
      return if dependency_requirements.any? || !unlock_subdependencies

      # If no definition was found and we're updating a sub-dependency,
      # try again but without unlocking any other sub-dependencies
      dependency_from_definition(unlock_subdependencies: false)
    end
    # rubocop:enable Metrics/PerceivedComplexity

    def subdependencies
      # If there's no lockfile we don't need to worry about
      # subdependencies
      return [] unless lockfile

      all_deps =  ::Bundler::LockfileParser.new(lockfile).
                  specs.map(&:name).map(&:to_s).uniq
      top_level = build_definition([]).dependencies.
                  map(&:name).map(&:to_s)

      all_deps - top_level
    end

    def build_definition(dependencies_to_unlock)
      # NOTE: we lock shared dependencies to avoid any top-level
      # dependencies getting unlocked (which would happen if they were
      # also subdependencies of the dependency being unlocked)
      ::Bundler::Definition.build(
        gemfile_name,
        lockfile_name,
        gems: dependencies_to_unlock,
        conservative: true
      )
    end

    def unlock_yanked_gem(dependencies_to_unlock, error)
      raise unless error.message.match?(GEM_NOT_FOUND_ERROR_REGEX)

      gem_name = error.message.match(GEM_NOT_FOUND_ERROR_REGEX).
                 named_captures["name"]
      raise if dependencies_to_unlock.include?(gem_name)

      dependencies_to_unlock << gem_name
    end

    def lockfile
      return @lockfile if defined?(@lockfile)

      @lockfile =
        begin
          return unless lockfile_name
          return unless File.exist?(lockfile_name)

          File.read(lockfile_name)
        end
    end

    def fetcher_class(dep)
      return unless dep.source.is_a?(::Bundler::Source::Rubygems)

      dep.source.fetchers.first.fetchers.first.class.to_s
    end

    def ruby_version
      return nil unless gemfile_name

      @ruby_version ||= build_definition([]).ruby_version&.gem_version
    end
  end
end
