# frozen_string_literal: true

require "json"

require "dependabot/dependency"
require "dependabot/nuget/file_parser"

# For details on dotnet-tools.json files see:
# https://learn.microsoft.com/en-us/dotnet/core/tools/local-tools-how-to-use
module Dependabot
  module Nuget
    class FileParser
      class DotNetToolsJsonParser
        require "dependabot/file_parsers/base/dependency_set"

        def initialize(dotnet_tools_json:)
          @dotnet_tools_json = dotnet_tools_json
        end

        def dependency_set
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          tools = parsed_dotnet_tools_json.fetch("tools", {})

          raise Dependabot::DependencyFileNotParseable, dotnet_tools_json.path unless tools.is_a?(Hash)

          tools.each do |dependency_name, node|
            raise Dependabot::DependencyFileNotParseable, dotnet_tools_json.path unless node.is_a?(Hash)

            version = node["version"]
            dependency_set <<
              Dependency.new(
                name: dependency_name,
                version: version,
                package_manager: "nuget",
                requirements: [{
                  requirement: version,
                  file: dotnet_tools_json.name,
                  groups: ["dependencies"],
                  source: nil
                }]
              )
          end

          dependency_set
        end

        private

        attr_reader :dotnet_tools_json

        def parsed_dotnet_tools_json
          @parsed_dotnet_tools_json ||= JSON.parse(dotnet_tools_json.content)
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, dotnet_tools_json.path
        end
      end
    end
  end
end
