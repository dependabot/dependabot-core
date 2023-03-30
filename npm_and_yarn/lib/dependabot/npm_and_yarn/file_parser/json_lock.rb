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

        def dependencies
          recursively_fetch_dependencies(parsed)
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

        def recursively_fetch_dependencies(object_with_dependencies)
          dependency_set = Dependabot::NpmAndYarn::FileParser::DependencySet.new

          dependencies = object_with_dependencies["dependencies"]
          dependencies ||= object_with_dependencies.fetch("packages", {}).transform_keys do |name|
            name.delete_prefix("node_modules/")
          end

          dependencies.each do |name, details|
            next if name.empty? # v3 lockfiles include an empty key holding info of the current package

            version = Version.semver_for(details["version"])
            next unless version

            dependency_args = {
              name: name,
              version: version,
              package_manager: "npm_and_yarn",
              requirements: []
            }

            if details["bundled"]
              dependency_args[:subdependency_metadata] =
                [{ npm_bundled: details["bundled"] }]
            end

            if details["dev"]
              dependency_args[:subdependency_metadata] =
                [{ production: !details["dev"] }]
            end

            dependency_set << Dependency.new(**dependency_args)
            dependency_set += recursively_fetch_dependencies(details)
          end

          dependency_set
        end

        def node_modules_path(manifest_name, dependency_name)
          return "node_modules/#{dependency_name}" if manifest_name == "package.json"

          workspace_path = manifest_name.gsub("/package.json", "")
          File.join(workspace_path, "node_modules", dependency_name)
        end
      end
    end
  end
end
