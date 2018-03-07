# frozen_string_literal: true

require "toml-rb"

require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module FileParsers
    module Python
      class Pip < Dependabot::FileParsers::Base
        require "dependabot/file_parsers/base/dependency_set"

        DEPENDENCY_GROUP_KEYS = [
          {
            pipfile: "packages",
            lockfile: "default"
          },
          {
            pipfile: "dev-packages",
            lockfile: "develop"
          }
        ].freeze

        def parse
          dependency_set = DependencySet.new
          dependency_set += requirement_and_setup_file_dependencies
          dependency_set += pipfile_dependencies if pipfile && lockfile
          dependency_set += lockfile_dependencies if pipfile && lockfile
          dependency_set.dependencies
        end

        private

        def requirement_and_setup_file_dependencies
          dependencies = DependencySet.new
          parsed_requirement_and_setup_files.each do |dep|
            dependencies <<
              Dependency.new(
                name: dep["name"],
                version: dep["version"]&.include?("*") ? nil : dep["version"],
                requirements: [
                  {
                    requirement: dep["requirement"],
                    file: Pathname.new(dep["file"]).cleanpath.to_path,
                    source: nil,
                    groups: []
                  }
                ],
                package_manager: "pip"
              )
          end
          dependencies
        end

        def pipfile_dependencies
          dependencies = DependencySet.new

          DEPENDENCY_GROUP_KEYS.each do |keys|
            next unless parsed_pipfile[keys[:pipfile]]

            parsed_pipfile[keys[:pipfile]].map do |dep_name, req|
              next unless req.is_a?(String) || req["version"]
              next unless dependency_version(dep_name, keys[:lockfile])

              dependencies <<
                Dependency.new(
                  name: normalised_name(dep_name),
                  version: dependency_version(dep_name, keys[:lockfile]),
                  requirements: [
                    {
                      requirement: req.is_a?(String) ? req : req["version"],
                      file: pipfile.name,
                      source: nil,
                      groups: [keys[:lockfile]]
                    }
                  ],
                  package_manager: "pipfile"
                )
            end
          end

          dependencies
        end

        # Create a DependencySet where each element has no requirement. Any
        # requirements will be added when combining the DependencySet with
        # other DependencySets.
        def lockfile_dependencies
          dependencies = DependencySet.new

          DEPENDENCY_GROUP_KEYS.map { |h| h.fetch(:lockfile) }.each do |key|
            next unless parsed_lockfile[key]

            parsed_lockfile[key].each do |dep_name, details|
              next unless details["version"]

              dependencies <<
                Dependency.new(
                  name: dep_name,
                  version: details["version"]&.gsub(/^==/, ""),
                  requirements: [],
                  package_manager: "pipfile"
                )
            end
          end

          dependencies
        end

        def parsed_requirement_and_setup_files
          SharedHelpers.in_a_temporary_directory do
            write_temporary_dependency_files

            SharedHelpers.run_helper_subprocess(
              command: "python3.6 #{python_helper_path}",
              function: "parse",
              args: [Dir.pwd]
            )
          end
        rescue SharedHelpers::HelperSubprocessFailed => error
          raise unless error.message.start_with?("InstallationError")
          raise Dependabot::DependencyFileNotEvaluatable, error.message
        end

        def write_temporary_dependency_files
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end
        end

        def python_helper_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/python/run.py")
        end

        def dependency_version(dep_name, group)
          parsed_lockfile.
            dig(group, normalised_name(dep_name), "version")&.
            gsub(/^==/, "")
        end

        # See https://www.python.org/dev/peps/pep-0503/#normalized-names
        def normalised_name(name)
          name.downcase.tr("_", "-").tr(".", "-")
        end

        def check_required_files
          filenames = dependency_files.map(&:name)
          return if filenames.any? { |name| name.match?(/requirements/x) }
          return if (%w(Pipfile Pipfile.lock) - filenames).empty?
          return if get_original_file("setup.py")
          raise "No requirements.txt or setup.py!"
        end

        def parsed_pipfile
          TomlRB.parse(pipfile.content)
        end

        def parsed_lockfile
          JSON.parse(lockfile.content)
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
