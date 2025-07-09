# typed: strict
# frozen_string_literal: true

require "toml-rb"

require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/uv/file_parser"
require "dependabot/uv/requirement"
require "dependabot/errors"
require "dependabot/uv/name_normaliser"

module Dependabot
  module Uv
    class FileParser
      class PyprojectFilesParser
        extend T::Sig
        POETRY_DEPENDENCY_TYPES = %w(dependencies dev-dependencies).freeze

        # https://python-poetry.org/docs/dependency-specification/
        UNSUPPORTED_DEPENDENCY_TYPES = %w(git path url).freeze

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependency_set
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          dependency_set += pyproject_dependencies if using_poetry? || using_pep621?  || using_pep735?
          dependency_set += lockfile_dependencies if using_poetry? && lockfile

          dependency_set
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def pyproject_dependencies
          if using_poetry?
            poetry_dependencies
          else
            pep621_pep735_dependencies
          end
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def poetry_dependencies
          @poetry_dependencies ||= T.let(parse_poetry_dependencies, T.untyped)
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def parse_poetry_dependencies
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

          POETRY_DEPENDENCY_TYPES.each do |type|
            deps_hash = T.must(poetry_root)[type] || {}
            dependencies += parse_poetry_dependency_group(type, deps_hash)
          end

          groups = T.must(poetry_root)["group"] || {}
          groups.each do |group, group_spec|
            dependencies += parse_poetry_dependency_group(group, group_spec["dependencies"])
          end
          dependencies
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def pep621_pep735_dependencies
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

          # PDM is not yet supported, so we want to ignore it for now because in
          # the current state of things, going on would result in updating
          # pyproject.toml but leaving pdm.lock out of sync, which is
          # undesirable. Leave PDM alone until properly supported
          return dependencies if using_pdm?

          parse_pep621_pep735_dependencies.each do |dep|
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
                package_manager: "uv"
              )
          end

          dependencies
        end

        sig do
          params(type: String,
                 deps_hash: T::Hash[String,
                                    T.untyped]).returns(Dependabot::FileParsers::Base::DependencySet)
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
              package_manager: "uv"
            )
          end
          dependencies
        end

        sig { params(name: String, extras: T::Array[String]).returns(String) }
        def normalised_name(name, extras)
          NameNormaliser.normalise_including_extras(name, extras)
        end

        # @param req can be an Array, Hash or String that represents the constraints for a dependency
        sig { params(req: T.untyped, type: String).returns(T::Array[T::Hash[Symbol, T.nilable(String)]]) }
        def parse_requirements_from(req, type)
          [req].flatten.compact.filter_map do |requirement|
            next if requirement.is_a?(Hash) && UNSUPPORTED_DEPENDENCY_TYPES.intersect?(requirement.keys)

            check_requirements(requirement)

            if requirement.is_a?(String)
              {
                requirement: requirement,
                file: T.must(pyproject).name,
                source: nil,
                groups: [type]
              }
            else
              {
                requirement: requirement["version"],
                file: T.must(pyproject).name,
                source: requirement.fetch("source", nil),
                groups: [type]
              }
            end
          end
        end

        sig { returns(T.nilable(T::Boolean)) }
        def using_poetry?
          !poetry_root.nil?
        end

        sig { returns(T::Boolean) }
        def using_pep621?
          !parsed_pyproject.dig("project", "dependencies").nil? ||
            !parsed_pyproject.dig("project", "optional-dependencies").nil? ||
            !parsed_pyproject.dig("build-system", "requires").nil?
        end

        sig { returns(T::Boolean) }
        def using_pep735?
          parsed_pyproject.key?("dependency-groups")
        end

        sig { returns(T.nilable(T::Hash[String, T.untyped])) }
        def poetry_root
          parsed_pyproject.dig("tool", "poetry")
        end

        sig { returns(T.untyped) }
        def using_pdm?
          using_pep621? && pdm_lock
        end

        # Create a DependencySet where each element has no requirement. Any
        # requirements will be added when combining the DependencySet with
        # other DependencySets.
        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
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
                package_manager: "uv",
                subdependency_metadata: [{
                  production: production_dependency_names.include?(name)
                }]
              )
          end

          dependencies
        end

        sig { returns(T::Array[T.nilable(String)]) }
        def production_dependency_names
          @production_dependency_names ||= T.let(parse_production_dependency_names,
                                                 T.nilable(T::Array[T.nilable(String)]))
        end

        sig { returns(T::Array[T.nilable(String)]) }
        def parse_production_dependency_names
          SharedHelpers.in_a_temporary_directory do
            File.write(T.must(pyproject).name, T.must(pyproject).content)
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

        sig { params(dep_name: String).returns(T.untyped) }
        def version_from_lockfile(dep_name)
          return unless parsed_lockfile

          parsed_lockfile.fetch("package", [])
                         .find { |p| normalise(p.fetch("name")) == normalise(dep_name) }
                         &.fetch("version", nil)
        end

        sig { params(req: T.untyped).returns(T::Array[Dependabot::Uv::Requirement]) }
        def check_requirements(req)
          requirement = req.is_a?(String) ? req : req["version"]
          Uv::Requirement.requirements_array(requirement)
        rescue Gem::Requirement::BadRequirementError => e
          raise Dependabot::DependencyFileNotEvaluatable, e.message
        end

        sig { params(name: String).returns(String) }
        def normalise(name)
          NameNormaliser.normalise(name)
        end

        sig { returns(T.untyped) }
        def parsed_pyproject
          @parsed_pyproject ||= T.let(TomlRB.parse(T.must(pyproject).content), T.untyped)
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          raise Dependabot::DependencyFileNotParseable, T.must(pyproject).path
        end

        sig { returns(T.untyped) }
        def parsed_poetry_lock
          @parsed_poetry_lock ||= T.let(TomlRB.parse(T.must(poetry_lock).content), T.untyped)
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          raise Dependabot::DependencyFileNotParseable, T.must(poetry_lock).path
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pyproject
          @pyproject ||= T.let(dependency_files.find { |f| f.name == "pyproject.toml" },
                               T.nilable(Dependabot::DependencyFile))
        end

        sig { returns(T.untyped) }
        def lockfile
          poetry_lock
        end

        sig { returns(T.untyped) }
        def parse_pep621_pep735_dependencies
          SharedHelpers.in_a_temporary_directory do
            write_temporary_pyproject

            SharedHelpers.run_helper_subprocess(
              command: "pyenv exec python3 #{NativeHelpers.python_helper_path}",
              function: "parse_pep621_pep735_dependencies",
              args: [T.must(pyproject).name]
            )
          end
        end

        sig { returns(Integer) }
        def write_temporary_pyproject
          path = T.must(pyproject).name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, T.must(pyproject).content)
        end

        sig { returns(T.untyped) }
        def parsed_lockfile
          parsed_poetry_lock if poetry_lock
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def poetry_lock
          @poetry_lock ||= T.let(dependency_files.find { |f| f.name == "poetry.lock" },
                                 T.nilable(Dependabot::DependencyFile))
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pdm_lock
          @pdm_lock ||= T.let(dependency_files.find { |f| f.name == "pdm.lock" },
                              T.nilable(Dependabot::DependencyFile))
        end
      end
    end
  end
end
