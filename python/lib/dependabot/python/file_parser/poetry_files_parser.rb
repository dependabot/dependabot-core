# frozen_string_literal: true

require "toml-rb"

require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/python/file_parser"
require "dependabot/python/requirement"
require "dependabot/errors"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class FileParser
      class PoetryFilesParser
        POETRY_DEPENDENCY_TYPES = %w(dependencies dev-dependencies).freeze

        # https://python-poetry.org/docs/dependency-specification/
        UNSUPPORTED_DEPENDENCY_TYPES = %w(git path url).freeze

        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        def dependency_set
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          dependency_set += pyproject_dependencies
          dependency_set += lockfile_dependencies if lockfile

          dependency_set
        end

        private

        attr_reader :dependency_files

        def pyproject_dependencies
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

          POETRY_DEPENDENCY_TYPES.each do |type|
            deps_hash = parsed_pyproject.dig("tool", "poetry", type) || {}

            deps_hash.each do |name, req|
              next if normalise(name) == "python"

              requirements = parse_requirements_from(req, type)
              next if requirements.empty?

              dependencies << Dependency.new(
                name: normalise(name),
                version: version_from_lockfile(name),
                requirements: requirements,
                package_manager: "pip"
              )
            end
          end

          dependencies
        end

        # @param req can be an Array, Hash or String that represents the constraints for a dependency
        def parse_requirements_from(req, type)
          [req].flatten.compact.filter_map do |requirement|
            next if requirement.is_a?(Hash) && (UNSUPPORTED_DEPENDENCY_TYPES & requirement.keys).any?

            check_requirements(requirement)

            {
              requirement: requirement.is_a?(String) ? requirement : requirement["version"],
              file: pyproject.name,
              source: nil,
              groups: [type]
            }
          end
        end

        # Create a DependencySet where each element has no requirement. Any
        # requirements will be added when combining the DependencySet with
        # other DependencySets.
        def lockfile_dependencies
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

          parsed_lockfile.fetch("package", []).each do |details|
            next if %w(directory git url).include?(details.dig("source", "type"))

            dependencies <<
              Dependency.new(
                name: normalise(details.fetch("name")),
                version: details.fetch("version"),
                requirements: [],
                package_manager: "pip",
                subdependency_metadata: [{
                  production: details["category"] != "dev"
                }]
              )
          end

          dependencies
        end

        def version_from_lockfile(dep_name)
          return unless parsed_lockfile

          parsed_lockfile.fetch("package", []).
            find { |p| normalise(p.fetch("name")) == normalise(dep_name) }&.
            fetch("version", nil)
        end

        def check_requirements(req)
          requirement = req.is_a?(String) ? req : req["version"]
          Python::Requirement.requirements_array(requirement)
        rescue Gem::Requirement::BadRequirementError => e
          raise Dependabot::DependencyFileNotEvaluatable, e.message
        end

        def normalise(name)
          NameNormaliser.normalise(name)
        end

        def parsed_pyproject
          @parsed_pyproject ||= TomlRB.parse(pyproject.content)
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          raise Dependabot::DependencyFileNotParseable, pyproject.path
        end

        def parsed_pyproject_lock
          @parsed_pyproject_lock ||= TomlRB.parse(pyproject_lock.content)
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          raise Dependabot::DependencyFileNotParseable, pyproject_lock.path
        end

        def parsed_poetry_lock
          @parsed_poetry_lock ||= TomlRB.parse(poetry_lock.content)
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          raise Dependabot::DependencyFileNotParseable, poetry_lock.path
        end

        def pyproject
          @pyproject ||=
            dependency_files.find { |f| f.name == "pyproject.toml" }
        end

        def lockfile
          poetry_lock || pyproject_lock
        end

        def parsed_lockfile
          return parsed_poetry_lock if poetry_lock
          return parsed_pyproject_lock if pyproject_lock
        end

        def pyproject_lock
          @pyproject_lock ||=
            dependency_files.find { |f| f.name == "pyproject.lock" }
        end

        def poetry_lock
          @poetry_lock ||=
            dependency_files.find { |f| f.name == "poetry.lock" }
        end
      end
    end
  end
end
