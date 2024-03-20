# typed: strict
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
        extend T::Sig

        require "dependabot/file_parsers/base/dependency_set"

        sig { params(global_json: Dependabot::DependencyFile).void }
        def initialize(global_json:)
          @global_json = global_json
          @parsed_global_json = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
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

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :global_json

        sig { returns(T::Hash[String, T.untyped]) }
        def parsed_global_json
          # Remove BOM if present as JSON should be UTF-8
          content = T.must(global_json.content)
          @parsed_global_json ||= JSON.parse(content.delete_prefix("\uFEFF"))
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, global_json.path
        end
      end
    end
  end
end
