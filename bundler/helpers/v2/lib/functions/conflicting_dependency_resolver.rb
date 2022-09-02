# frozen_string_literal: true

module Functions
  class ConflictingDependencyResolver
    def initialize(dependency_name:, target_version:, lockfile_name:)
      @dependency_name = dependency_name
      @target_version = target_version
      @lockfile_name = lockfile_name
    end

    # Finds any dependencies in the lockfile that have a subdependency on the
    # given dependency that does not satisfly the target_version.
    # @return [Array<Hash{String => String}]
    #   * explanation [String] a sentence explaining the conflict
    #   * name [String] the blocking dependencies name
    #   * version [String] the version of the blocking dependency
    #   * requirement [String] the requirement on the target_dependency
    def conflicting_dependencies
      Bundler.settings.set_command_option("only_update_to_newer_versions", true)

      parent_specs.flat_map do |parent_spec|
        top_level_specs_for(parent_spec).map do |top_level|
          dependency = parent_spec.dependencies.find { |bd| bd.name == dependency_name }
          {
            "explanation" => explanation(parent_spec, dependency, top_level),
            "name" => parent_spec.name,
            "version" => parent_spec.version.to_s,
            "requirement" => dependency.requirement.to_s
          }
        end
      end
    end

    private

    attr_reader :dependency_name, :target_version, :lockfile_name

    def parent_specs
      version = Gem::Version.new(target_version)
      parsed_lockfile.specs.filter do |spec|
        spec.dependencies.any? do |dep|
          dep.name == dependency_name &&
            !dep.requirement.satisfied_by?(version)
        end
      end
    end

    def top_level_specs_for(parent_spec)
      return [parent_spec] if top_level?(parent_spec)

      parsed_lockfile.specs.filter do |spec|
        spec.dependencies.any? do |dep|
          dep.name == parent_spec.name && top_level?(spec)
        end
      end
    end

    def top_level?(spec)
      parsed_lockfile.dependencies.key?(spec.name)
    end

    def explanation(spec, dependency, top_level)
      if spec.name == top_level.name
        "#{spec.name} (#{spec.version}) requires #{dependency_name} (#{dependency.requirement})"
      else
        "#{top_level.name} (#{top_level.version}) requires #{dependency_name} " \
          "(#{dependency.requirement}) via #{spec.name} (#{spec.version})"
      end
    end

    def parsed_lockfile
      @parsed_lockfile ||= Bundler::LockfileParser.new(lockfile)
    end

    def lockfile
      return @lockfile if defined?(@lockfile)

      @lockfile =
        begin
          return unless lockfile_name && File.exist?(lockfile_name)

          File.read(lockfile_name)
        end
    end
  end
end
