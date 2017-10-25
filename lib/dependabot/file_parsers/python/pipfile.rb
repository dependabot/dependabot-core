# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module FileParsers
    module Python
      class Pipfile < Dependabot::FileParsers::Base
        def parse
          dependency_versions.map do |dep|
            Dependency.new(
              name: dep["name"],
              version: dep["version"],
              requirements: [
                {
                  requirement: dep["requirement"],
                  file: pipfile.name,
                  source: nil,
                  groups: [dep["group"]]
                }
              ],
              package_manager: "pipfile"
            )
          end.compact
        end

        private

        def dependency_versions
          SharedHelpers.in_a_temporary_directory do
            File.write("Pipfile", pipfile.content)
            File.write("Pipfile.lock", lockfile.content)

            SharedHelpers.run_helper_subprocess(
              command: "python3.6 #{python_helper_path}",
              function: "parse_pipfile",
              args: [Dir.pwd]
            )
          end
        end

        def python_helper_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/python/run.py")
        end

        def check_required_files
          %w(Pipfile Pipfile.lock).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def pipfile
          @pipfile ||= get_original_file("Pipfile")
        end

        def lockfile
          @lockfile ||= get_original_file("Pipfile.lock")
        end
      end
    end
  end
end
