# typed: strict
# frozen_string_literal: true

require "pathname"
require "sorbet-runtime"
require "yaml"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/package_manager"

module Dependabot
  module NpmAndYarn
    # The local files that a pnpm-workspace.yaml delegates settings to with `include` (pnpm 12.15+), for example a
    # catalog moved to its own file:
    #
    #   include:
    #     ./pnpm-catalogs.yaml: [catalogs]
    #
    # A local source starts with `./` or `../`, names a `.yaml` or `.yml` file, and resolves from the workspace root.
    # Any other source is a config dependency, which lives in node_modules rather than in the repository.
    # See https://pnpm.io/config-includes.
    module PnpmWorkspaceIncludes
      extend T::Sig

      LOCAL_SOURCE = %r{\A\.\.?/.+\.ya?ml\z}

      # Paths of the included files, in the same form as the workspace file's name (relative to the job directory).
      sig { params(workspace_file: Dependabot::DependencyFile).returns(T::Array[String]) }
      def self.included_file_paths(workspace_file)
        config = YAML.safe_load(workspace_file.content.to_s, aliases: true)
        return [] unless config.is_a?(Hash)

        include_map = config["include"]
        return [] unless include_map.is_a?(Hash)

        workspace_dir = Pathname.new(File.dirname(workspace_file.name))
        include_map.keys.filter_map do |source|
          next unless source.is_a?(String) && source.match?(LOCAL_SOURCE)

          workspace_dir.join(source).cleanpath.to_s
        end.uniq
      rescue Psych::Exception
        # An unparseable workspace file is reported where it is parsed for its own settings.
        []
      end

      sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).returns(T::Array[Dependabot::DependencyFile]) }
      def self.included_files(dependency_files)
        paths = dependency_files
                .select { |f| File.basename(f.name) == PNPMPackageManager::PNPM_WS_YML_FILENAME }
                .flat_map { |f| included_file_paths(f) }
        return [] if paths.empty?

        dependency_files.select { |f| paths.include?(f.name) }
      end
    end
  end
end
