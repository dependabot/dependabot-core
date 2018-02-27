# frozen_string_literal: true

require "toml-rb"

require "dependabot/dependency"
require "dependabot/file_parsers/base"

module Dependabot
  module FileParsers
    module Python
      class Pipfile < Dependabot::FileParsers::Base
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
          dependency_set += pipfile_dependencies
          dependency_set += lockfile_dependencies
          dependency_set.dependencies
        end

        private

        def check_required_files
          %w(Pipfile Pipfile.lock).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
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

        def dependency_version(dep_name, group)
          parsed_lockfile.
            dig(group, normalised_name(dep_name), "version")&.
            gsub(/^==/, "")
        end

        # See https://www.python.org/dev/peps/pep-0503/#normalized-names
        def normalised_name(name)
          name.downcase.tr("_", "-").tr(".", "-")
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
