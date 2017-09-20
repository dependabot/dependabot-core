# frozen_string_literal: true
require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"

module Dependabot
  module FileParsers
    module JavaScript
      class Yarn < Dependabot::FileParsers::Base
        DEPENDENCY_TYPES =
          %w(dependencies devDependencies optionalDependencies).freeze

        def parse
          dependency_versions.map do |dep|
            dep_group = group(dep["name"])

            Dependency.new(
              name: dep["name"],
              version: dep["version"],
              package_manager: "yarn",
              requirements: [{
                requirement: parsed_package_json.dig(dep_group, dep["name"]),
                file: "package.json",
                source: nil,
                groups: [dep_group]
              }]
            )
          end
        end

        private

        def dependency_versions
          SharedHelpers.in_a_temporary_directory do
            File.write("package.json", package_json.content)
            File.write("yarn.lock", yarn_lock.content)

            SharedHelpers.run_helper_subprocess(
              command: "node #{js_helper_path}",
              function: "parse",
              args: [Dir.pwd]
            )
          end
        end

        def js_helper_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/javascript/bin/run.js")
        end

        def check_required_files
          %w(package.json yarn.lock).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def package_json
          @package_json ||= get_original_file("package.json")
        end

        def group(dep_name)
          DEPENDENCY_TYPES.each do |type|
            return type if parsed_package_json.dig(type, dep_name)
          end

          raise "Expected to find dependency #{dep_name} in one of "\
                "#{DEPENDENCY_TYPES.join(', ')} but it wasn't "\
                "found in any of them!"
        end

        def parsed_package_json
          JSON.parse(package_json.content)
        end

        def yarn_lock
          @yarn_lock ||= get_original_file("yarn.lock")
        end
      end
    end
  end
end
