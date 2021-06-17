# frozen_string_literal: true

module Functions
  class ForceUpdater
    class TransitiveDependencyError < StandardError; end

    def initialize(dependency_name:, target_version:, gemfile_name:,
                   lockfile_name:, update_multiple_dependencies:)
      @dependency_name = dependency_name
      @target_version = target_version
      @gemfile_name = gemfile_name
      @lockfile_name = lockfile_name
      @update_multiple_dependencies = update_multiple_dependencies
    end

    def run
      # Only allow upgrades. Otherwise it's unlikely that this
      # resolution will be found by the FileUpdater
      Bundler.settings.set_command_option(
        "only_update_to_newer_versions",
        true
      )

      dependencies_to_unlock = []

      begin
        definition = build_definition(dependencies_to_unlock: dependencies_to_unlock)
        definition.resolve_remotely!
        specs = definition.resolve
        updates = [{ name: dependency_name }] +
                  dependencies_to_unlock.map { |dep| { name: dep.name } }
        specs = specs.map do |dep|
          {
            name: dep.name,
            version: dep.version
          }
        end
        [updates, specs]
      rescue Bundler::VersionConflict => e
        raise unless update_multiple_dependencies?

        # TODO: Not sure this won't unlock way too many things...
        new_dependencies_to_unlock =
          new_dependencies_to_unlock_from(
            error: e,
            already_unlocked: dependencies_to_unlock
          )

        raise if new_dependencies_to_unlock.none?

        dependencies_to_unlock += new_dependencies_to_unlock
        retry
      end
    end

    private

    attr_reader :dependency_name, :target_version, :gemfile_name,
                :lockfile_name, :credentials,
                :update_multiple_dependencies
    alias update_multiple_dependencies? update_multiple_dependencies

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

    def build_definition(dependencies_to_unlock:)
      gems_to_unlock = dependencies_to_unlock.map(&:name) + [dependency_name]
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

      dep = definition.dependencies.
            find { |d| d.name == dependency_name }

      # If the dependency is not found in the Gemfile it means this is a
      # transitive dependency that we can't force update.
      raise TransitiveDependencyError unless dep

      # Set the requirement for the gem we're forcing an update of
      new_req = Gem::Requirement.create("= #{target_version}")
      dep.instance_variable_set(:@requirement, new_req)
      dep.source = nil if dep.source.is_a?(Bundler::Source::Git)

      definition
    end

    def lockfile
      return @lockfile if defined?(@lockfile)

      @lockfile =
        begin
          return unless lockfile_name && File.exist?(lockfile_name)

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
  end
end
