# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"

module Dependabot
  module FileParsers
    module JavaScript
      class Npm < Dependabot::FileParsers::Base
        DEPENDENCY_TYPES =
          %w(dependencies devDependencies optionalDependencies).freeze
        CENTRAL_REGISTRY_URL = "https://registry.npmjs.org"

        def parse
          DEPENDENCY_TYPES.flat_map do |type|
            deps = parsed_package_json[type] || {}
            deps.map do |name, requirement|
              dep = parsed_package_lock_json.dig("dependencies", name)

              next unless dep&.fetch("resolved", nil)

              Dependency.new(
                name: name,
                version: dep["version"],
                package_manager: "yarn",
                requirements: [{
                  requirement: requirement,
                  file: "package.json",
                  groups: [type],
                  source: source_for(dep)
                }]
              )
            end
          end.compact
        end

        private

        def check_required_files
          %w(package.json package-lock.json).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def source_for(dep)
          return if dep["resolved"].start_with?(CENTRAL_REGISTRY_URL)
          url =
            if dep["resolved"].include?("/~/")
              dep["resolved"].split("/~/").first
            else
              dep["resolved"].split("/")[0..2].join("/")
            end

          {
            type: "private_registry",
            url: url
          }
        end

        def package_json
          @package_json ||= get_original_file("package.json")
        end

        def parsed_package_json
          JSON.parse(package_json.content)
        end

        def package_lock
          @package_lock ||= get_original_file("package-lock.json")
        end

        def parsed_package_lock_json
          JSON.parse(package_lock.content)
        end
      end
    end
  end
end
