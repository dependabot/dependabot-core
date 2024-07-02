# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/nuget/native_discovery/native_discovery_json_reader"
require "dependabot/nuget/native_helpers"
require "sorbet-runtime"

# For details on how dotnet handles version constraints, see:
# https://docs.microsoft.com/en-us/nuget/reference/package-versioning
module Dependabot
  module Nuget
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"
      require_relative "cache_manager"

      sig { returns(T::Hash[String, T::Array[Dependabot::Dependency]]) }
      def self.file_dependency_cache
        T.let(CacheManager.cache("file_parser.parse"), T::Hash[String, T::Array[Dependabot::Dependency]])
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        return [] unless repo_contents_path

        key = NativeDiscoveryJsonReader.create_cache_key(dependency_files)
        workspace_path = source&.directory || "/"
        self.class.file_dependency_cache[key] ||= begin
          # run discovery for the repo
          discovery_json_path = NativeDiscoveryJsonReader.create_discovery_file_path_from_dependency_files(
            dependency_files
          )
          NativeHelpers.run_nuget_discover_tool(repo_root: T.must(repo_contents_path),
                                                workspace_path: workspace_path,
                                                output_path: discovery_json_path,
                                                credentials: credentials)

          discovery_json = NativeDiscoveryJsonReader.discovery_json_from_path(discovery_json_path)
          return [] unless discovery_json

          Dependabot.logger.info("Discovery JSON content: #{discovery_json.content}")
          discovery_json_reader = NativeDiscoveryJsonReader.new(
            discovery_json: discovery_json
          )

          # cache discovery results
          NativeDiscoveryJsonReader.set_discovery_from_dependency_files(dependency_files: dependency_files,
                                                                        discovery: discovery_json_reader)
          discovery_json_reader.dependency_set.dependencies
        end

        T.must(self.class.file_dependency_cache[key])
      end

      private

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def proj_files
        projfile = /\.proj$/

        dependency_files.select do |df|
          df.name.match?(projfile)
        end
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def project_files
        projectfile = /\.(cs|vb|fs)proj$/

        dependency_files.select do |df|
          df.name.match?(projectfile)
        end
      end

      sig { override.void }
      def check_required_files
        return if project_files.any? || proj_files.any?

        raise Dependabot::DependencyFileNotFound.new(
          "*.(cs|vb|fs)proj, *.proj",
          "No project file or *.proj!"
        )
      end
    end
  end
end

Dependabot::FileParsers.register("nuget", Dependabot::Nuget::FileParser)
