# frozen_string_literal: true

require "toml-rb"

require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/python/file_parser"
require "dependabot/errors"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class FileParser
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
              group = keys[:lockfile]
              next unless specifies_version?(req)
              next if git_or_path_requirement?(req)
              next if pipfile_lock && !dependency_version(dep_name, req, group)

              # Empty requirements are not allowed in Dependabot::Dependency and
              # equivalent to "*" (latest available version)
              req = "*" if req == ""

              dependencies <<
                Dependency.new(
                  name: normalised_name(dep_name),
                  version: dependency_version(dep_name, req, group),
                  requirements: [{
                    requirement: req.is_a?(String) ? req : req["version"],
                    file: pipfile.name,
                    source: nil,
                    groups: [group]
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
          return dependencies unless pipfile_lock

          DEPENDENCY_GROUP_KEYS.map { |h| h.fetch(:lockfile) }.each do |key|
            next unless parsed_pipfile_lock[key]

            parsed_pipfile_lock[key].each do |dep_name, details|
              version = case details
                        when String then details
                        when Hash then details["version"]
                        end
              next unless version
              next if git_or_path_requirement?(details)

              dependencies <<
                Dependency.new(
                  name: dep_name,
                  version: version&.gsub(/^===?/, ""),
                  requirements: [],
                  package_manager: "pip",
                  subdependency_metadata: [{ production: key != "develop" }]
                )
            end
          end

          dependencies
        end

        def dependency_version(dep_name, requirement, group)
          req = version_from_hash_or_string(requirement)

          if pipfile_lock
            details = parsed_pipfile_lock.
                      dig(group, normalised_name(dep_name))

            version = version_from_hash_or_string(details)
            version&.gsub(/^===?/, "")
          elsif req.start_with?("==") && !req.include?("*")
            req.strip.gsub(/^===?/, "")
          end
        end

        def version_from_hash_or_string(obj)
          case obj
          when String then obj.strip
          when Hash then obj["version"]
          end
        end

        def specifies_version?(req)
          return true if req.is_a?(String)

          req["version"]
        end

        def git_or_path_requirement?(req)
          return false unless req.is_a?(Hash)

          %w(git path).any? { |k| req.key?(k) }
        end

        def normalised_name(name)
          NameNormaliser.normalise(name)
        end

        def parsed_pipfile
          @parsed_pipfile ||= TomlRB.parse(pipfile.content)
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
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
