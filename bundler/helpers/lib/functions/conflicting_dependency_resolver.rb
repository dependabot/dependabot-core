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
    #   * name [String] the blocking dependencies name
    #   * version [String] the version of the blocking dependency
    #   * requirement [String] the requirement on the target_dependency
    def conflicting_dependencies
      Bundler.settings.set_command_option("only_update_to_newer_versions", true)

      parent_specs.map do |spec|
        req = spec.dependencies.find { |bd| bd.name == dependency_name }
        {
          "explanation" => "#{spec.name} (#{spec.version}) requires #{dependency_name} (#{req.requirement})",
          "name" => spec.name,
          "version" => spec.version.to_s,
          "requirement" => req.requirement.to_s
        }
      end
    end

    private

    attr_reader :dependency_name, :target_version, :lockfile_name

    def parent_specs
      version = Gem::Version.new(target_version)
      Bundler::LockfileParser.new(lockfile).specs.filter do |spec|
        spec.dependencies.any? do |sub_dep|
          sub_dep.name == dependency_name &&
            !sub_dep.requirement.satisfied_by?(version)
        end
      end
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
