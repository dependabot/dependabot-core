module Functions
  class VersionResolver
    GEM_NOT_FOUND_ERROR_REGEX = /locked to (?<name>[^\s]+) \(/.freeze

    attr_reader :dependency_name, :dependency_requirements,
                :gemfile_name, :lockfile_name,
                :dir, :credentials

    def initialize(dependency_name:, dependency_requirements:,
                   gemfile_name:, lockfile_name:, using_bundler_2:,
                   dir:, credentials:)
      @dependency_name = dependency_name
      @dependency_requirements = dependency_requirements
      @gemfile_name = gemfile_name
      @lockfile_name = lockfile_name
      @using_bundler_2 = using_bundler_2
      @dir = dir
      @credentials = @credentials
    end

    def version_details
      setup_bundler

      dep = dependency_from_definition

      # TODO: Rewrite this
      #
      # If the dependency wasn't found in the definition, but *is*
      # included in a gemspec, it's because the Gemfile didn't import
      # the gemspec. This is unusual, but the correct behaviour if/when
      # it happens is to behave as if the repo was gemspec-only.
      if dep.nil? && dependency_requirements.any?
        return "latest"
      end

      # Otherwise, if the dependency wasn't found it's because it is a
      # subdependency that was removed when attempting to update it.
      return nil if dep.nil?

      # If the dependency is Bundler itself then we can't trust the
      # version that has been returned (it's the version Dependabot is
      # running on, rather than the true latest resolvable version).
      return nil if dep.name == "bundler"

      # If the old Gemfile index was used then it won't have checked
      # Ruby compatibility. Fix that by doing the check manually (and
      # saying no update is possible if the Ruby version is a mismatch)
      return nil if ruby_version_incompatible?(dep)

      details = { version: dep.version }
      if dep.source.instance_of?(::Bundler::Source::Git)
        details[:commit_sha] = dep.source.revision
      end
      details
    end

    private

    def using_bundler_2?
      @using_bundler_2
    end

    def setup_bundler
      ::Bundler.instance_variable_set(:@root, dir)

      # TODO: DRY out this setup with Functions::LockfileUpdater
      return unless credentials
      credentials.each do |cred|
        token = cred["token"] ||
                "#{cred['username']}:#{cred['password']}"

        ::Bundler.settings.set_command_option(
          cred.fetch("host"),
          token.gsub("@", "%40F").gsub("?", "%3F")
        )
      end

      set_bundler_2_flags if using_bundler_2?
    end

    def set_bundler_2_flags
      ::Bundler.settings.set_command_option("forget_cli_options", "true")
      ::Bundler.settings.set_command_option("github.https", "true")
    end

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
      # Note: we lock shared dependencies to avoid any top-level
      # dependencies getting unlocked (which would happen if they were
      # also subdependencies of the dependency being unlocked)
      ::Bundler::Definition.build(
        gemfile_name,
        lockfile_name,
        gems: dependencies_to_unlock,
        lock_shared_dependencies: true
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

    def ruby_version_incompatible?(dep)
      return false unless dep.source.is_a?(::Bundler::Source::Rubygems)

      fetcher = dep.source.fetchers.first.fetchers.first

      # It's only the old index we have a problem with
      return false unless fetcher.is_a?(::Bundler::Fetcher::Dependency)

      # If no Ruby version is specified, we don't have a problem
      return false unless ruby_version

      versions = Excon.get(
        "#{fetcher.fetch_uri}api/v1/versions/#{dependency_name}.json",
        idempotent: true,
        **SharedHelpers.excon_defaults
      )

      # Give the benefit of the doubt if something goes wrong fetching
      # version details (could be that it's a private index, etc.)
      return false unless versions.status == 200

      ruby_requirement =
        JSON.parse(versions.body).
        find { |details| details["number"] == dep.version.to_s }&.
        fetch("ruby_version", nil)

      # Give the benefit of the doubt if we can't find the version's
      # required Ruby version.
      return false unless ruby_requirement

      ruby_requirement = Gem::Requirement.new(ruby_requirement)

      !ruby_requirement.satisfied_by?(ruby_version)
    rescue JSON::ParserError, Excon::Error::Socket, Excon::Error::Timeout
      # Give the benefit of the doubt if something goes wrong fetching
      # version details (could be that it's a private index, etc.)
      false
    end

    def ruby_version
      return nil unless gemfile_name

      @ruby_version ||= build_definition([]).ruby_version&.gem_version
    end
  end
end
