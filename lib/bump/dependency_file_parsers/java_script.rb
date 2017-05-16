# frozen_string_literal: true
require "json"
require "bump/dependency"
require "bump/dependency_file_parsers/base"
require "bump/dependency_file_fetchers/java_script"
require "bump/shared_helpers"

module Bump
  module DependencyFileParsers
    class JavaScript < Base
      def parse
        dependency_versions.map do |dep|
          Dependency.new(
            name: dep["name"],
            version: dep["version"],
            language: "javascript"
          )
        end
      end

      private

      def dependency_versions
        SharedHelpers.in_a_temporary_directory do |dir|
          File.write(File.join(dir, "package.json"), package_json.content)
          File.write(File.join(dir, "yarn.lock"), yarn_lock.content)

          SharedHelpers.run_helper_subprocess(
            command: "node #{js_helper_path}",
            function: "parse",
            args: [dir]
          )
        end
      end

      def js_helper_path
        project_root = File.join(File.dirname(__FILE__), "../../..")
        File.join(project_root, "helpers/javascript/bin/run.js")
      end

      def required_files
        Bump::DependencyFileFetchers::JavaScript.required_files
      end

      def package_json
        @package_json ||= get_original_file("package.json")
      end

      def yarn_lock
        @yarn_lock ||= get_original_file("yarn.lock")
      end

      def parser
        JSON.parse(package_json.content)
      end
    end
  end
end
