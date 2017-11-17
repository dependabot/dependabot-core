# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"

module Dependabot
  module FileParsers
    module JavaScript
      class Yarn < Dependabot::FileParsers::Base
        require "dependabot/file_parsers/base/dependency_set"

        DEPENDENCY_TYPES =
          %w(dependencies devDependencies optionalDependencies).freeze

        def parse
          dependency_set = DependencySet.new

          dependency_versions.each do |dep|
            dependency_set <<
              Dependency.new(
                name: dep["name"],
                version: dep["version"],
                package_manager: "yarn",
                requirements: [requirements_for(dep)]
              )
          end

          dependency_set.dependencies
        end

        private

        def dependency_versions
          SharedHelpers.in_a_temporary_directory do
            dependency_files.
              select { |f| f.name.end_with?("package.json") }.
              each do |file|
                path = file.name
                FileUtils.mkdir_p(Pathname.new(path).dirname)
                File.write(file.name, sanitized_package_json_content(file))
              end
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
          File.join(project_root, "helpers/yarn/bin/run.js")
        end

        def check_required_files
          %w(package.json yarn.lock).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def sanitized_package_json_content(file)
          file.content.gsub(/\{\{.*\}\}/, "something")
        end

        def requirements_for(dep)
          package_file = package_json_for(dep)
          parsed_package_json = JSON.parse(package_file.content)
          group = group_for(dep["name"], parsed_package_json)

          {
            requirement: parsed_package_json.dig(group, dep["name"]),
            file: package_file.name,
            source: nil,
            groups: [group]
          }
        end

        def package_json_for(dep)
          file = dependency_files.find { |f| f.name == dep["source_file"] }
          return file unless file.nil?

          raise "Unexpected file #{dep["source_file"]}"
        end

        def group_for(dep_name, parsed_package_json)
          DEPENDENCY_TYPES.each do |type|
            return type if parsed_package_json.dig(type, dep_name)
          end

          raise "Expected to find dependency #{dep_name} in one of "\
                "#{DEPENDENCY_TYPES.join(', ')} but it wasn't "\
                "found in any of them!"
        end

        def yarn_lock
          @yarn_lock ||= get_original_file("yarn.lock")
        end
      end
    end
  end
end
