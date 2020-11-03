# frozen_string_literal: true

module Functions
  class ParentDependencyResolver
    def initialize(dependency_name:, target_version:, lockfile_name:)
      @dependency_name = dependency_name
      @target_version = target_version
      @lockfile_name = lockfile_name

      Bundler.settings.set_command_option("only_update_to_newer_versions", true)
    end

    # @return [Array<Hash{Symbol => String}]
    #   :name the blocking dependencies name
    #   :version the version of the blocking dependency
    #   :requirement the requirement on the target_dependency
    def blocking_parent_dependencies
      parent_specs.map do |spec|
        req = spec.dependencies.find { |bd| bd.name == dependency_name }
        {
          name: spec.name,
          version: spec.version.to_s,
          requirement: req.requirement.to_s
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
