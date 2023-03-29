# frozen_string_literal: true

require "json"
require "dependabot/errors"
require "dependabot/npm_and_yarn/helpers"

module Dependabot
  module NpmAndYarn
    class FileParser
      class JsonLock
        def initialize(dependency_file)
          @dependency_file = dependency_file
        end

        def parsed
          @parsed ||= JSON.parse(@dependency_file.content)
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, @dependency_file.path
        end

        def details(dependency_name, _requirement, manifest_name)
          if Helpers.npm_version(@dependency_file.content) == "npm8"
            # NOTE: npm 8 sometimes doesn't install workspace dependencies in the
            # workspace folder so we need to fallback to checking top-level
            nested_details = parsed.dig("packages", node_modules_path(manifest_name, dependency_name))
            details = nested_details || parsed.dig("packages", "node_modules/#{dependency_name}")
            details&.slice("version", "resolved", "integrity", "dev")
          else
            parsed.dig("dependencies", dependency_name)
          end
        end

        private

        def node_modules_path(manifest_name, dependency_name)
          return "node_modules/#{dependency_name}" if manifest_name == "package.json"

          workspace_path = manifest_name.gsub("/package.json", "")
          File.join(workspace_path, "node_modules", dependency_name)
        end
      end
    end
  end
end
