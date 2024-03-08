# typed: strict
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
        extend T::Sig

        require "dependabot/file_parsers/base/dependency_set"

        sig { params(dotnet_tools_json: Dependabot::DependencyFile).void }
        def initialize(dotnet_tools_json:)
          @dotnet_tools_json = dotnet_tools_json
          @parsed_dotnet_tools_json = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
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

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :dotnet_tools_json

        sig { returns(T::Hash[String, T.untyped]) }
        def parsed_dotnet_tools_json
          # Remove BOM if present as JSON should be UTF-8
          content = T.must(dotnet_tools_json.content)
          @parsed_dotnet_tools_json ||= JSON.parse(content.delete_prefix("\uFEFF"))
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, dotnet_tools_json.path
        end
      end
    end
  end
end
