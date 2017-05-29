# frozen_string_literal: true
require "bump/dependency"
require "bump/file_parsers/base"
require "bump/file_fetchers/java_script/yarn"
require "bump/shared_helpers"

module Bump
  module FileParsers
    module JavaScript
      class Yarn < Bump::FileParsers::Base
        def parse
          dependency_versions.map do |dep|
            Dependency.new(
              name: dep["name"],
              version: dep["version"],
              package_manager: "yarn"
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
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/javascript/bin/run.js")
        end

        def required_files
          Bump::FileFetchers::JavaScript::Yarn.required_files
        end

        def package_json
          @package_json ||= get_original_file("package.json")
        end

        def yarn_lock
          @yarn_lock ||= get_original_file("yarn.lock")
        end
      end
    end
  end
end
