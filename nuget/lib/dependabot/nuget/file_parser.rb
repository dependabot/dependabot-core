# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/nuget/discovery/discovery_json_reader"
require "sorbet-runtime"

# For details on how dotnet handles version constraints, see:
# https://docs.microsoft.com/en-us/nuget/reference/package-versioning
module Dependabot
  module Nuget
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        workspace_path = project_files.first&.directory
        return [] unless workspace_path

        # run discovery for the repo
        NativeHelpers.run_nuget_discover_tool(repo_root: T.must(repo_contents_path),
                                              workspace_path: workspace_path,
                                              output_path: DiscoveryJsonReader.discovery_file_path,
                                              credentials: credentials)

        discovered_dependencies.dependencies
      end

      private

      sig { returns(Dependabot::FileParsers::Base::DependencySet) }
      def discovered_dependencies
        discovery_json = DiscoveryJsonReader.discovery_json
        return DependencySet.new unless discovery_json

        DiscoveryJsonReader.new(
          discovery_json: discovery_json
        ).dependency_set
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def project_files
        projfile = /\.([a-z]{2})?proj$/
        packageprops = /[Dd]irectory.[Pp]ackages.props/

        dependency_files.select do |df|
          df.name.match?(projfile) ||
            df.name.match?(packageprops)
        end
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def packages_config_files
        dependency_files.select do |f|
          f.name.split("/").last&.casecmp("packages.config")&.zero?
        end
      end

      sig { override.void }
      def check_required_files
        return if project_files.any? || packages_config_files.any?

        raise "No project file or packages.config!"
      end
    end
  end
end

Dependabot::FileParsers.register("nuget", Dependabot::Nuget::FileParser)
