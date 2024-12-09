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
        dependencies
      end

      private

      sig { returns(T::Array[Dependabot::Dependency]) }
      def dependencies
        @dependencies ||= T.let(begin
          directory = source&.directory || "/"
          discovery_json_reader = DiscoveryJsonReader.run_discovery_in_directory(
            repo_contents_path: T.must(repo_contents_path),
            directory: directory,
            credentials: credentials
          )
          discovery_json_reader.dependency_set.dependencies
        end, T.nilable(T::Array[Dependabot::Dependency]))
      end

      sig { override.void }
      def check_required_files
        requirement_files = dependencies.flat_map do |dep|
          dep.requirements.map { |r| T.let(r.fetch(:file), String) }
        end.uniq

        project_files = requirement_files.select { |f| File.basename(f).match?(/\.(cs|vb|fs)proj$/) }
        global_json_file = requirement_files.select { |f| File.basename(f) == "global.json" }
        dotnet_tools_json_file = requirement_files.select { |f| File.basename(f) == "dotnet-tools.json" }
        return if project_files.any? || global_json_file.any? || dotnet_tools_json_file.any?

        raise Dependabot::DependencyFileNotFound.new(
          "*.(cs|vb|fs)proj",
          "No project file."
        )
      end
    end
  end
end

Dependabot::FileParsers.register("nuget", Dependabot::Nuget::FileParser)
