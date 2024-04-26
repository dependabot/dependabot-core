# typed: strong
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/nuget/discovery/discovery_json_reader"
require "dependabot/nuget/native_helpers"
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

        # `workspace_path` is the only unique value here so we use it as the cache key
        cache = T.let(CacheManager.cache("file_parser.parse"), T::Hash[String, T::Array[Dependabot::Dependency]])
        key = workspace_path
        cache[key] ||= begin
          # run discovery for the repo
          NativeHelpers.run_nuget_discover_tool(repo_root: repo_contents_path,
                                                workspace_path: workspace_path,
                                                output_path: DiscoveryJsonReader.discovery_file_path,
                                                credentials: credentials)
          discovered_dependencies.dependencies
        end

        T.must(cache[key])
      end

      private

      sig { returns(Dependabot::FileParsers::Base::DependencySet) }
      def discovered_dependencies
        discovery_json = DiscoveryJsonReader.discovery_json
        return DependencySet.new unless discovery_json

        Dependabot.logger.info("Discovery JSON content: #{discovery_json.content}")

        DiscoveryJsonReader.new(
          discovery_json: discovery_json
        ).dependency_set
      end

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
