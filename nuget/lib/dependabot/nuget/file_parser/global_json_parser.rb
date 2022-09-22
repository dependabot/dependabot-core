# frozen_string_literal: true

require "json"

require "dependabot/dependency"
require "dependabot/nuget/file_parser"

# For details on global.json files see:
# https://docs.microsoft.com/en-us/dotnet/core/tools/global-json
module Dependabot
  module Nuget
    class FileParser
      class GlobalJsonParser
        require "dependabot/file_parsers/base/dependency_set"

        def initialize(global_json:)
          @global_json = global_json
        end

        def dependency_set
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          project_sdks = parsed_global_json.fetch("msbuild-sdks", {})

          raise Dependabot::DependencyFileNotParseable, global_json.path unless project_sdks.is_a?(Hash)

          project_sdks.each do |dependency_name, version|
            dependency_set <<
              Dependency.new(
                name: dependency_name,
                version: version,
                package_manager: "nuget",
                requirements: [{
                  requirement: version,
                  file: global_json.name,
                  groups: ["dependencies"],
                  source: nil
                }]
              )
          end

          dependency_set
        end

        private

        attr_reader :global_json

        def parsed_global_json
          @parsed_global_json ||= JSON.parse(global_json.content)
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, global_json.path
        end
      end
    end
  end
end
