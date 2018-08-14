# frozen_string_literal: true

require "toml-rb"

require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/file_parsers/python/pip"
require "dependabot/errors"

module Dependabot
  module FileParsers
    module Python
      class Pip
        class PipfileFilesParser
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

          def initialize(dependency_files:)
            @dependency_files = dependency_files
          end

          def dependency_set
            dependency_set = Dependabot::FileParsers::Base::DependencySet.new

            dependency_set += pipfile_dependencies
            dependency_set += pipfile_lock_dependencies

            dependency_set
          end

          private

          attr_reader :dependency_files

          def pipfile_dependencies
            dependencies = Dependabot::FileParsers::Base::DependencySet.new

            DEPENDENCY_GROUP_KEYS.each do |keys|
              next unless parsed_pipfile[keys[:pipfile]]

              parsed_pipfile[keys[:pipfile]].map do |dep_name, req|
                next unless req.is_a?(String) || req["version"]
                next unless dependency_version(dep_name, keys[:lockfile])

                dependencies <<
                  Dependency.new(
                    name: normalised_name(dep_name),
                    version: dependency_version(dep_name, keys[:lockfile]),
                    requirements: [{
                      requirement: req.is_a?(String) ? req : req["version"],
                      file: pipfile.name,
                      source: nil,
                      groups: [keys[:lockfile]]
                    }],
                    package_manager: "pip"
                  )
              end
            end

            dependencies
          end

          # Create a DependencySet where each element has no requirement. Any
          # requirements will be added when combining the DependencySet with
          # other DependencySets.
          def pipfile_lock_dependencies
            dependencies = Dependabot::FileParsers::Base::DependencySet.new

            DEPENDENCY_GROUP_KEYS.map { |h| h.fetch(:lockfile) }.each do |key|
              next unless parsed_pipfile_lock[key]

              parsed_pipfile_lock[key].each do |dep_name, details|
                next unless details["version"]

                dependencies <<
                  Dependency.new(
                    name: dep_name,
                    version: details["version"]&.gsub(/^===?/, ""),
                    requirements: [],
                    package_manager: "pip"
                  )
              end
            end

            dependencies
          end

          def dependency_version(dep_name, group)
            parsed_pipfile_lock.
              dig(group, normalised_name(dep_name), "version")&.
              gsub(/^===?/, "")
          end

          # See https://www.python.org/dev/peps/pep-0503/#normalized-names
          def normalised_name(name)
            name.downcase.tr("_", "-").tr(".", "-")
          end

          def parsed_pipfile
            @parsed_pipfile ||= TomlRB.parse(pipfile.content)
          rescue TomlRB::ParseError
            raise Dependabot::DependencyFileNotParseable, pipfile.path
          end

          def parsed_pipfile_lock
            @parsed_pipfile_lock ||= JSON.parse(pipfile_lock.content)
          rescue JSON::ParserError
            raise Dependabot::DependencyFileNotParseable, pipfile_lock.path
          end

          def pipfile
            @pipfile ||= dependency_files.find { |f| f.name == "Pipfile" }
          end

          def pipfile_lock
            @pipfile_lock ||=
              dependency_files.find { |f| f.name == "Pipfile.lock" }
          end
        end
      end
    end
  end
end
