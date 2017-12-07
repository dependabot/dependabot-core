# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"

module Dependabot
  module FileParsers
    module JavaScript
      class NpmAndYarn < Dependabot::FileParsers::Base
        require "dependabot/file_parsers/base/dependency_set"

        DEPENDENCY_TYPES =
          %w(dependencies devDependencies optionalDependencies).freeze
        CENTRAL_REGISTRIES = %w(
          https://registry.npmjs.org
          https://registry.yarnpkg.com
        ).freeze

        def parse
          dependency_set = DependencySet.new

          package_files.each do |file|
            DEPENDENCY_TYPES.each do |type|
              deps = JSON.parse(file.content)[type] || {}
              deps.each do |name, requirement|
                dep = build_dependency(
                  file: file, type: type, name: name, requirement: requirement
                )
                dependency_set << dep if dep
              end
            end
          end

          dependency_set.dependencies
        end

        private

        # rubocop:disable Metrics/CyclomaticComplexity
        def build_dependency(file:, type:, name:, requirement:)
          lockfile_details = lockfile_details(name)
          return if lockfile? && !lockfile_details
          return if lockfile? && !lockfile_details["resolved"]
          return if requirement.include?("/")

          Dependency.new(
            name: name,
            version: lockfile_details&.fetch("version", nil),
            package_manager: yarn_lock ? "yarn" : "npm",
            requirements: [{
              requirement: requirement,
              file: file.name,
              groups: [type],
              source: source_for(name)
            }]
          )
        end
        # rubocop:enable Metrics/CyclomaticComplexity

        def check_required_files
          raise "No package.json!" unless get_original_file("package.json")
        end

        def source_for(name)
          details = lockfile_details(name)
          return unless details

          if CENTRAL_REGISTRIES.any? { |u| details["resolved"].start_with?(u) }
            return
          end

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

        def lockfile_details(name)
          if package_lock && parsed_package_lock_json.dig("dependencies", name)
            parsed_package_lock_json.dig("dependencies", name)
          elsif yarn_lock && parsed_yarn_lock.find { |dep| dep["name"] == name }
            parsed_yarn_lock.find { |dep| dep["name"] == name }
          end
        end

        def parsed_package_lock_json
          JSON.parse(package_lock.content)
        end

        def parsed_yarn_lock
          @parsed_yarn_lock ||=
            SharedHelpers.in_a_temporary_directory do
              dependency_files.
                select { |f| f.name.end_with?("package.json") }.
                each do |file|
                  path = file.name
                  FileUtils.mkdir_p(Pathname.new(path).dirname)
                  File.write(file.name, sanitized_package_json_content(file))
                end
              File.write("yarn.lock", yarn_lock.content)

              project_root = File.join(File.dirname(__FILE__), "../../../..")
              helper_path = File.join(project_root, "helpers/yarn/bin/run.js")

              SharedHelpers.run_helper_subprocess(
                command: "node #{helper_path}",
                function: "parse",
                args: [Dir.pwd]
              )
            end
        end

        def package_files
          dependency_files.select { |f| f.name.end_with?("package.json") }
        end

        def sanitized_package_json_content(file)
          file.content.gsub(/\{\{.*\}\}/, "something")
        end

        def lockfile?
          yarn_lock || package_lock
        end

        def package_lock
          @package_lock ||= get_original_file("package-lock.json")
        end

        def yarn_lock
          @yarn_lock ||= get_original_file("yarn.lock")
        end
      end
    end
  end
end
