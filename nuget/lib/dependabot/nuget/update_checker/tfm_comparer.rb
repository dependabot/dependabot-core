# frozen_string_literal: true

require "excon"
require "nokogiri"

require "dependabot/nuget/version"
require "dependabot/nuget/requirement"
require "dependabot/nuget/native_helpers"
require "dependabot/nuget/update_checker"
require "dependabot/shared_helpers"

module Dependabot
  module Nuget
    class UpdateChecker
      class TfmComparer
        require "dependabot/nuget/file_parser/project_file_parser"

        def initialize(dependency_files:, credentials:)
          @dependency_files       = dependency_files
          @credentials            = credentials
        end

        def are_frameworks_compatible?(package_tfms)
          return false if package_tfms.empty?
          return false if project_tfms.empty?

          key = "project_ftms:#{project_tfms.join(',')}:package_tfms:#{package_tfms.sort.join(',')}"

          @cached_framework_check ||= {}
          @cached_framework_check[key] ||= NativeHelpers.run_nuget_framework_check(project_tfms, package_tfms)
          @cached_framework_check[key]
        end

        private

        attr_reader :dependency_files, :credentials

        def project_tfms
          @project_tfms ||= begin
            tfms = Set.new
            (project_files + project_import_files).each do |file|
              parser = project_file_parser
              discovered_tfms = parser.target_frameworks(project_file: file)
              tfms += discovered_tfms unless discovered_tfms.nil?
            end
            tfms.to_a.sort
          end
        end

        def project_file_parser
          @project_file_parser ||=
            FileParser::ProjectFileParser.new(
              dependency_files: dependency_files,
              credentials: credentials
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
end
