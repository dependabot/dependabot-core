# typed: strict
# frozen_string_literal: true

require "nokogiri"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "sorbet-runtime"

# For details on how dotnet handles version constraints, see:
# https://docs.microsoft.com/en-us/nuget/reference/package-versioning
module Dependabot
  module Nuget
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"
      require_relative "file_parser/project_file_parser"
      require_relative "file_parser/packages_config_parser"
      require_relative "file_parser/global_json_parser"
      require_relative "file_parser/dotnet_tools_json_parser"

      PACKAGE_CONF_DEPENDENCY_SELECTOR = "packages > packages"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        dependency_set = DependencySet.new
        dependency_set += project_file_dependencies
        dependency_set += packages_config_dependencies
        dependency_set += global_json_dependencies if global_json
        dependency_set += dotnet_tools_json_dependencies if dotnet_tools_json

        (dependencies, deps_with_unresolved_versions) = dependency_set.dependencies.partition do |d|
          # try to parse the version; don't care about result, just that it succeeded
          _ = Version.new(d.version)
          true
        rescue ArgumentError
          # version could not be parsed
          false
        end

        deps_with_unresolved_versions.each do |d|
          Dependabot.logger.warn "Dependency '#{d.name}' excluded due to unparsable version: #{d.version}"
        end

        dependencies
      end

      private

      sig { returns(Dependabot::FileParsers::Base::DependencySet) }
      def project_file_dependencies
        dependency_set = DependencySet.new

        (project_files + project_import_files).each do |file|
          parser = project_file_parser
          dependency_set += parser.dependency_set(project_file: file)
        end

        dependency_set
      end

      sig { returns(Dependabot::FileParsers::Base::DependencySet) }
      def packages_config_dependencies
        dependency_set = DependencySet.new

        packages_config_files.each do |file|
          parser = PackagesConfigParser.new(packages_config: file)
          dependency_set += parser.dependency_set
        end

        dependency_set
      end

      sig { returns(Dependabot::FileParsers::Base::DependencySet) }
      def global_json_dependencies
        return DependencySet.new unless global_json

        GlobalJsonParser.new(global_json: T.must(global_json)).dependency_set
      end

      sig { returns(Dependabot::FileParsers::Base::DependencySet) }
      def dotnet_tools_json_dependencies
        return DependencySet.new unless dotnet_tools_json

        DotNetToolsJsonParser.new(dotnet_tools_json: T.must(dotnet_tools_json)).dependency_set
      end

      sig { returns(Dependabot::Nuget::FileParser::ProjectFileParser) }
      def project_file_parser
        @project_file_parser ||= T.let(
          ProjectFileParser.new(
            dependency_files: dependency_files,
            credentials: credentials,
            repo_contents_path: @repo_contents_path
          ),
          T.nilable(Dependabot::Nuget::FileParser::ProjectFileParser)
        )
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

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def project_import_files
        dependency_files -
          project_files -
          packages_config_files -
          nuget_configs -
          [global_json] -
          [dotnet_tools_json]
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def nuget_configs
        dependency_files.select { |f| f.name.match?(/nuget\.config$/i) }
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def global_json
        dependency_files.find { |f| f.name.casecmp("global.json")&.zero? }
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def dotnet_tools_json
        dependency_files.find { |f| f.name.casecmp(".config/dotnet-tools.json")&.zero? }
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
