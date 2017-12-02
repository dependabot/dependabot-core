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
              lockfile_details = lockfile_details(name)

              next if package_lock && !lockfile_details
              next if package_lock && !lockfile_details["resolved"]

              Dependency.new(
                name: name,
                version: lockfile_details&.fetch("version", nil),
                package_manager: "yarn",
                requirements: [{
                  requirement: requirement,
                  file: "package.json",
                  groups: [type],
                  source: source_for(name)
                }]
              )
            end
          end.compact
        end

        private

        def check_required_files
          raise "No package.json!" unless get_original_file("package.json")
        end

        def source_for(name)
          details = lockfile_details(name)
          return unless details
          return if details["resolved"].start_with?(CENTRAL_REGISTRY_URL)
          url =
            if details["resolved"].include?("/~/")
              details["resolved"].split("/~/").first
            else
              details["resolved"].split("/")[0..2].join("/")
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

        def lockfile_details(name)
          return nil unless package_lock
          parsed_package_lock_json.dig("dependencies", name)
        end

        def parsed_package_lock_json
          JSON.parse(package_lock.content)
        end
      end
    end
  end
end
