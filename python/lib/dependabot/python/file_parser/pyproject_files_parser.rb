# typed: true
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
      class PyprojectFilesParser
        POETRY_DEPENDENCY_TYPES = %w(dependencies dev-dependencies).freeze

        # https://python-poetry.org/docs/dependency-specification/
        UNSUPPORTED_DEPENDENCY_TYPES = %w(git path url).freeze

        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        def dependency_set
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          dependency_set += pyproject_dependencies if using_poetry? || using_pep621?
          dependency_set += lockfile_dependencies if using_poetry? && lockfile

          dependency_set
        end

        private

        attr_reader :dependency_files

        def pyproject_dependencies
          if using_poetry?
            missing_keys = missing_poetry_keys

            if missing_keys.any?
              raise DependencyFileNotParseable.new(
                pyproject.path,
                "#{pyproject.path} is missing the following sections:\n" \
                "  * #{missing_keys.map { |key| "tool.poetry.#{key}" }.join("\n  * ")}\n"
              )
            end

            poetry_dependencies
          else
            pep621_dependencies
          end
        end

        def poetry_dependencies
          @poetry_dependencies ||= parse_poetry_dependencies
        end

        def parse_poetry_dependencies
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

          POETRY_DEPENDENCY_TYPES.each do |type|
            deps_hash = poetry_root[type] || {}
            dependencies += parse_poetry_dependency_group(type, deps_hash)
          end

          groups = poetry_root["group"] || {}
          groups.each do |group, group_spec|
            dependencies += parse_poetry_dependency_group(group, group_spec["dependencies"])
          end
          dependencies
        end

        def pep621_dependencies
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

          # PDM is not yet supported, so we want to ignore it for now because in
          # the current state of things, going on would result in updating
          # pyproject.toml but leaving pdm.lock out of sync, which is
          # undesirable. Leave PDM alone until properly supported
          return dependencies if using_pdm?

          parsed_pep621_dependencies.each do |dep|
            # If a requirement has a `<` or `<=` marker then updating it is
            # probably blocked. Ignore it.
            next if dep["markers"].include?("<")

            # If no requirement, don't add it
            next if dep["requirement"].empty?

            dependencies <<
              Dependency.new(
                name: normalised_name(dep["name"], dep["extras"]),
                version: dep["version"]&.include?("*") ? nil : dep["version"],
                requirements: [{
                  requirement: dep["requirement"],
                  file: Pathname.new(dep["file"]).cleanpath.to_path,
                  source: nil,
                  groups: [dep["requirement_type"]].compact
                }],
                package_manager: "pip"
              )
          end

          dependencies
        end

        def parse_poetry_dependency_group(type, deps_hash)
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

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
          dependencies
        end

        def normalised_name(name, extras)
          NameNormaliser.normalise_including_extras(name, extras)
        end

        # @param req can be an Array, Hash or String that represents the constraints for a dependency
        def parse_requirements_from(req, type)
          [req].flatten.compact.filter_map do |requirement|
            next if requirement.is_a?(Hash) && UNSUPPORTED_DEPENDENCY_TYPES.intersect?(requirement.keys)

            check_requirements(requirement)

            if requirement.is_a?(String)
              {
                requirement: requirement,
                file: pyproject.name,
                source: nil,
                groups: [type]
              }
            else
              {
                requirement: requirement["version"],
                file: pyproject.name,
                source: requirement.fetch("source", nil),
                groups: [type]
              }
            end
          end
        end

        def using_poetry?
          !poetry_root.nil?
        end

        def missing_poetry_keys
          package_mode = poetry_root.fetch("package-mode", true)
          required_keys = package_mode ? %w(name version description authors) : []
          required_keys.reject { |key| poetry_root.key?(key) }
        end

        def using_pep621?
          !parsed_pyproject.dig("project", "dependencies").nil? ||
            !parsed_pyproject.dig("project", "optional-dependencies").nil?
        end

        def poetry_root
          parsed_pyproject.dig("tool", "poetry")
        end

        def using_pdm?
          using_pep621? && pdm_lock
        end

        # Create a DependencySet where each element has no requirement. Any
        # requirements will be added when combining the DependencySet with
        # other DependencySets.
        def lockfile_dependencies
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

          source_types = %w(directory git url)
          parsed_lockfile.fetch("package", []).each do |details|
            next if source_types.include?(details.dig("source", "type"))

            name = normalise(details.fetch("name"))

            dependencies <<
              Dependency.new(
                name: name,
                version: details.fetch("version"),
                requirements: [],
                package_manager: "pip",
                subdependency_metadata: [{
                  production: production_dependency_names.include?(name)
                }]
              )
          end

          dependencies
        end

        def production_dependency_names
          @production_dependency_names ||= parse_production_dependency_names
        end

        def parse_production_dependency_names
          SharedHelpers.in_a_temporary_directory do
            File.write(pyproject.name, pyproject.content)
            File.write(lockfile.name, lockfile.content)

            begin
              output = SharedHelpers.run_shell_command("pyenv exec poetry show --only main")

              output.split("\n").map { |line| line.split.first }
            rescue SharedHelpers::HelperSubprocessFailed
              # Sometimes, we may be dealing with an old lockfile that our
              # poetry version can't show dependency information for. Other
              # commands we use like `poetry update` are more resilient and
              # automatically heal the lockfile. So we rescue the error and make
              # a best effort approach to this.
              poetry_dependencies.dependencies.filter_map do |dep|
                dep.name if dep.production?
              end
            end
          end
        end

        def version_from_lockfile(dep_name)
          return unless parsed_lockfile

          parsed_lockfile.fetch("package", [])
                         .find { |p| normalise(p.fetch("name")) == normalise(dep_name) }
                         &.fetch("version", nil)
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
          poetry_lock
        end

        def parsed_pep621_dependencies
          SharedHelpers.in_a_temporary_directory do
            write_temporary_pyproject

            SharedHelpers.run_helper_subprocess(
              command: "pyenv exec python3 #{NativeHelpers.python_helper_path}",
              function: "parse_pep621_dependencies",
              args: [pyproject.name]
            )
          end
        end

        def write_temporary_pyproject
          path = pyproject.name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, pyproject.content)
        end

        def parsed_lockfile
          parsed_poetry_lock if poetry_lock
        end

        def poetry_lock
          @poetry_lock ||=
            dependency_files.find { |f| f.name == "poetry.lock" }
        end

        def pdm_lock
          @pdm_lock ||=
            dependency_files.find { |f| f.name == "pdm.lock" }
        end
      end
    end
  end
end
