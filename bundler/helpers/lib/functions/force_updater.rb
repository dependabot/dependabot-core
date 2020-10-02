module Functions
  class ForceUpdater
    def initialize(dir:, dependency_name:, target_version:, gemfile_name:,
                   lockfile_name:, using_bundler_2:, credentials:,
                   update_multiple_dependencies:)
      @dir = dir
      @dependency_name = dependency_name
      @target_version = target_version
      @gemfile_name = gemfile_name
      @lockfile_name = lockfile_name
      @using_bundler_2 = using_bundler_2
      @credentials = credentials
      @update_multiple_dependencies = update_multiple_dependencies
    end

    def run
      # Remove installed gems from the default Rubygems index
      Gem::Specification.all =
        Gem::Specification.send(:default_stubs, "*.gemspec")

      # Set flags and credentials
      set_bundler_flags_and_credentials

      other_updates = []

      begin
        definition = build_definition(other_updates: other_updates)
        definition.resolve_remotely!
        specs = definition.resolve
        updates = [{ name: dependency_name }] +
          other_updates.map { |dep| { name: dep.name } }
        specs = specs.map do |dep|
          {
            name: dep.name,
            version: dep.version,
          }
        end
        [updates, specs]
      rescue Bundler::VersionConflict => e
        raise unless update_multiple_dependencies?

        # TODO: Not sure this won't unlock way too many things...
        new_dependencies_to_unlock =
          new_dependencies_to_unlock_from(
            error: e,
            already_unlocked: other_updates
          )

        raise if new_dependencies_to_unlock.none?

        other_updates += new_dependencies_to_unlock
        retry
      end
    end

    private

    attr_reader :dir, :dependency_name, :target_version, :gemfile_name,
                :lockfile_name, :using_bundler_2, :credentials,
                :update_multiple_dependencies
    alias :using_bundler_2? :using_bundler_2
    alias :update_multiple_dependencies? :update_multiple_dependencies

    def new_dependencies_to_unlock_from(error:, already_unlocked:)
      potentials_deps =
        relevant_conflicts(error, already_unlocked).
        flat_map(&:requirement_trees).
        reject do |tree|
          # If the final requirement wasn't specific, it can't be binding
          next true if tree.last.requirement == Gem::Requirement.new(">= 0")

          # If the conflict wasn't for the dependency we're updating then
          # we don't have enough info to reject it
          next false unless tree.last.name == dependency_name

          # If the final requirement *was* for the dependency we're updating
          # then we can ignore the tree if it permits the target version
          tree.last.requirement.satisfied_by?(
            Gem::Version.new(target_version)
          )
        end.map(&:first)

      potentials_deps.
        reject { |dep| already_unlocked.map(&:name).include?(dep.name) }.
        reject { |dep| [dependency_name, "ruby\0"].include?(dep.name) }.
        uniq
    end

    def relevant_conflicts(error, dependencies_being_unlocked)
      names = [*dependencies_being_unlocked.map(&:name), dependency_name]

      # For a conflict to be relevant to the updates we're making it must be
      # 1) caused by a new requirement introduced by our unlocking, or
      # 2) caused by an old requirement that prohibits the update.
      # Hence, we look at the beginning and end of the requirement trees
      error.cause.conflicts.values.
        select do |conflict|
          conflict.requirement_trees.any? do |t|
            names.include?(t.last.name) || names.include?(t.first.name)
          end
        end
    end

    def build_definition(other_updates:)
      gems_to_unlock = other_updates.map(&:name) + [dependency_name]
      definition = Bundler::Definition.build(
        gemfile_name,
        lockfile_name,
        gems: gems_to_unlock + subdependencies,
        lock_shared_dependencies: true
      )

      # Remove the Gemfile / gemspec requirements on the gems we're
      # unlocking (i.e., completely unlock them)
      gems_to_unlock.each do |gem_name|
        unlock_gem(definition: definition, gem_name: gem_name)
      end

      # Set the requirement for the gem we're forcing an update of
      new_req = Gem::Requirement.create("= #{target_version}")
      definition.dependencies.
        find { |d| d.name == dependency_name }.
        tap do |dep|
          dep.instance_variable_set(:@requirement, new_req)
          dep.source = nil if dep.source.is_a?(Bundler::Source::Git)
        end

      definition
    end

    def lockfile
      return @lockfile if defined?(@lockfile)

      @lockfile =
        begin
          return unless File.exist?(lockfile_name)

          File.read(lockfile_name)
        end
    end

    def subdependencies
      # If there's no lockfile we don't need to worry about
      # subdependencies
      return [] unless lockfile

      all_deps =  Bundler::LockfileParser.new(lockfile).
                  specs.map(&:name).map(&:to_s)
      top_level = Bundler::Definition.
                  build(gemfile_name, lockfile_name, {}).
                  dependencies.map(&:name).map(&:to_s)

      all_deps - top_level
    end

    def unlock_gem(definition:, gem_name:)
      dep = definition.dependencies.find { |d| d.name == gem_name }
      version = definition.locked_gems.specs.
                find { |d| d.name == gem_name }.version

      dep&.instance_variable_set(
        :@requirement,
        Gem::Requirement.create(">= #{version}")
      )
    end

    def set_bundler_flags_and_credentials
      # Set auth details
      credentials.each do |cred|
        token = cred["token"] ||
                "#{cred['username']}:#{cred['password']}"

        Bundler.settings.set_command_option(
          cred.fetch("host"),
          token.gsub("@", "%40F").gsub("?", "%3F")
        )
      end

      # Only allow upgrades. Otherwise it's unlikely that this
      # resolution will be found by the FileUpdater
      Bundler.settings.set_command_option(
        "only_update_to_newer_versions",
        true
      )

      # Use HTTPS for GitHub if lockfile was generated by Bundler 2
      set_bundler_2_flags if using_bundler_2?
    end

    def set_bundler_2_flags
      Bundler.settings.set_command_option("forget_cli_options", "true")
      Bundler.settings.set_command_option("github.https", "true")
    end
  end
end
