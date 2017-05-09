# frozen_string_literal: true
require "gemnasium/parser"
require "bundler"
require "bump/dependency_file"
require "bump/shared_helpers"

module Bump
  module DependencyFileUpdaters
    class Javascript
      attr_reader :package_json, :yarn_lock, :dependency

      def initialize(dependency_files:, dependency:, github_access_token:)
        @package_json = dependency_files.find { |f| f.name == "package.json" }
        @yarn_lock = dependency_files.find { |file| file.name == "yarn.lock" }
        validate_files_are_present!

        @github_access_token = github_access_token
        @dependency = dependency
      end

      def updated_dependency_files
        [updated_package_json_file, updated_yarn_lock]
      end

      def updated_package_json_file
        DependencyFile.new(
          name: "package.json",
          content: updated_package_json_content
        )
      end

      def updated_yarn_lock
        DependencyFile.new(
          name: "yarn.lock",
          content: updated_yarn_lock_content
        )
      end

      private

      def validate_files_are_present!
        raise "No package.json!" unless package_json
        raise "No yarn.lock!" unless yarn_lock
      end

      def updated_package_json_content
        return @updated_package_json_content if @updated_package_json_content

        parsed_content = JSON.parse(@package_json.content)

        %w(dependencies devDependencies).each do |dep_type|
          old_version_string = parsed_content.dig(dep_type, dependency.name)
          next unless old_version_string

          parsed_content[dep_type][dependency.name] =
            updated_version_string(old_version_string, dependency.version)
        end

        @updated_package_json_content =
          JSON.pretty_generate(parsed_content) + "\n"
      end

      def updated_yarn_lock_content
        return @updated_yarn_lock_content if @updated_yarn_lock_content
        SharedHelpers.in_a_temporary_directory do |dir|
          File.write(File.join(dir, "yarn.lock"), @yarn_lock.content)
          File.write(File.join(dir, "package.json"),
                     updated_package_json_content)
          `cd #{dir} && yarn install --ignore-scripts 2>&1`
          @updated_yarn_lock_content =
            File.read(File.join(dir, "yarn.lock"))
        end
      end

      def updated_version_string(old_version_string, new_version_number)
        old_version_string.sub(/[\d\.]*\d/) do |old_version_number|
          precision = old_version_number.split(".").count
          new_version_number.split(".").first(precision).join(".")
        end
      end
    end
  end
end
