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
      dependencies_to_unlock = []

      begin
        definition = build_definition(dependencies_to_unlock: dependencies_to_unlock)
        definition.resolve_remotely!
        specs = definition.resolve
        updates = ([dependency_name, *dependencies_to_unlock] - subdependencies).uniq.map { |name| { name: name } }
        specs = specs.map do |dep|
          {
            name: dep.name,
            version: dep.version
          }
        end
        [updates, specs]
      rescue Bundler::SolveFailure => e
        raise unless update_multiple_dependencies?

        # TODO: Not sure this won't unlock way too many things...
        new_dependencies_to_unlock =
          new_dependencies_to_unlock_from(
            error: e,
            already_unlocked: dependencies_to_unlock
          )

        raise if new_dependencies_to_unlock.none?

        dependencies_to_unlock |= new_dependencies_to_unlock
        retry
      end
    end

    private

    attr_reader :dependency_name, :target_version, :gemfile_name,
                :lockfile_name, :credentials,
                :update_multiple_dependencies
    alias update_multiple_dependencies? update_multiple_dependencies

    def new_dependencies_to_unlock_from(error:, already_unlocked:)
      names = [*already_unlocked, dependency_name]
      extra_names_to_unlock = []

      incompatibility = error.cause.incompatibility

      while incompatibility.conflict?
        cause = incompatibility.cause
        incompatibility = cause.incompatibility

        incompatibility.terms.each do |term|
          name = term.package.name
          extra_names_to_unlock << name unless names.include?(name)
        end
      end

      extra_names_to_unlock
    end

    def build_definition(dependencies_to_unlock:)
      gems_to_unlock = dependencies_to_unlock + [dependency_name]
      definition = Bundler::Definition.build(
        gemfile_name,
        lockfile_name,
        gems: gems_to_unlock + subdependencies,
        conservative: true
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
                  specs.map(&:name)
      top_level = Bundler::Definition.
                  build(gemfile_name, lockfile_name, {}).
                  dependencies.map(&:name)

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
