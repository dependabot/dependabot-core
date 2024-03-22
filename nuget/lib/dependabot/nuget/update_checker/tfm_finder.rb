# typed: true
# frozen_string_literal: true

require "excon"
require "nokogiri"

require "dependabot/update_checkers/base"
require "dependabot/nuget/version"
require "dependabot/nuget/requirement"
require "dependabot/nuget/native_helpers"
require "dependabot/shared_helpers"

module Dependabot
  module Nuget
    class TfmFinder
      require "dependabot/nuget/file_parser/packages_config_parser"
      require "dependabot/nuget/file_parser/project_file_parser"

      def initialize(dependency_files:, credentials:, repo_contents_path:)
        @dependency_files       = dependency_files
        @credentials            = credentials
        @repo_contents_path     = repo_contents_path
      end

      def frameworks(dependency)
        tfms = Set.new
        tfms += project_file_tfms(dependency)
        tfms += project_import_file_tfms
        tfms.to_a
      end

      private

      attr_reader :dependency_files
      attr_reader :credentials
      attr_reader :repo_contents_path

      def project_file_tfms(dependency)
        project_files_with_dependency(dependency).flat_map do |file|
          project_file_parser.target_frameworks(project_file: file)
        end
      end

      def project_files_with_dependency(dependency)
        project_files.select do |file|
          packages_config_contains_dependency?(file, dependency) ||
            project_file_contains_dependency?(file, dependency)
        end
      end

      def packages_config_contains_dependency?(file, dependency)
        config_file = find_packages_config_file(file)
        return false unless config_file

        config_parser = FileParser::PackagesConfigParser.new(packages_config: config_file)
        config_parser.dependency_set.dependencies.any? do |d|
          d.name.casecmp(dependency.name)&.zero?
        end
      end

      def project_file_contains_dependency?(file, dependency)
        project_file_parser.dependency_set(project_file: file).dependencies.any? do |d|
          d.name.casecmp(dependency.name)&.zero?
        end
      end

      def find_packages_config_file(file)
        return file if file.name.end_with?("packages.config")

        filename = File.basename(file.name)
        search_path = file.name.sub(filename, "packages.config")

        dependency_files.find { |f| f.name.casecmp(search_path).zero? }
      end

      def project_import_file_tfms
        @project_import_file_tfms ||= project_import_files.flat_map do |file|
          project_file_parser.target_frameworks(project_file: file)
        end
      end

      def project_file_parser
        @project_file_parser ||=
          FileParser::ProjectFileParser.new(
            dependency_files: dependency_files,
            credentials: credentials,
            repo_contents_path: repo_contents_path
          )
      end

      def project_files
        projfile = /\.[a-z]{2}proj$/
        packageprops = /[Dd]irectory.[Pp]ackages.props/

        dependency_files.select do |df|
          df.name.match?(projfile) ||
            df.name.match?(packageprops)
        end
      end

      def packages_config_files
        dependency_files.select do |f|
          f.name.split("/").last.casecmp("packages.config").zero?
        end
      end

      def project_import_files
        dependency_files -
          project_files -
          packages_config_files -
          nuget_configs -
          [global_json] -
          [dotnet_tools_json]
      end

      def nuget_configs
        dependency_files.select { |f| f.name.match?(/nuget\.config$/i) }
      end

      def global_json
        dependency_files.find { |f| f.name.casecmp("global.json").zero? }
      end

      def dotnet_tools_json
        dependency_files.find { |f| f.name.casecmp(".config/dotnet-tools.json").zero? }
      end
    end
  end
end
