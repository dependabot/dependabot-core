# typed: strong
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
        extend T::Sig

        POETRY_DEPENDENCY_TYPES = %w(dependencies dev-dependencies).freeze

        # https://python-poetry.org/docs/dependency-specification/
        # Git dependencies with tags are now supported for version tracking
        UNSUPPORTED_DEPENDENCY_TYPES = %w(path url).freeze

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
          @pyproject_document = T.let(nil, T.nilable(PyprojectDocument))
          @poetry_lock_document = T.let(nil, T.nilable(PoetryLock))
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependency_set
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          dependency_set += pyproject_dependencies if using_poetry? || using_pep621? || using_pep735?
          dependency_set += lockfile_dependencies if using_poetry? && lockfile

          dependency_set
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def pyproject_dependencies
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

          dependencies += poetry_dependencies if using_poetry?
          dependencies += pep621_pep735_dependencies if using_pep621? || using_pep735?

          dependencies
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def poetry_dependencies
          @poetry_dependencies ||= T.let(parse_poetry_dependencies, T.nilable(Dependabot::FileParsers::Base::DependencySet))
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def parse_poetry_dependencies
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

          POETRY_DEPENDENCY_TYPES.each do |type|
            dependencies += parse_poetry_dependency_group(type, pyproject_document.poetry_dependencies(type))
          end

          pyproject_document.poetry_groups.each do |group, dependencies_by_name|
            dependencies += parse_poetry_dependency_group(group, dependencies_by_name)
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
            next if skip_pep621_dep?(dep)

            dependencies <<
              Dependency.new(
                name: normalise(dep.name),
                version: dep.version&.include?("*") ? nil : dep.version,
                requirements: [{
                  requirement: dep.requirement,
                  file: Pathname.new(dep.file).cleanpath.to_path,
                  source: nil,
                  groups: [dep.requirement_type].compact
                }],
                package_manager: "pip",
                metadata: extras_metadata(dep.extras).merge(
                  source_requirement: dep.source_requirement
                ).compact
              )
          end

          dependencies
        end

        sig do
          params(
            type: String,
            deps_hash: PyprojectDocument::PoetryDependencyMap
          ).returns(Dependabot::FileParsers::Base::DependencySet)
        end
        def parse_poetry_dependency_group(type, deps_hash)
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

          deps_hash.each do |name, requirements_data|
            next if normalise(name) == "python"

            requirements = parse_requirements_from(requirements_data, type)
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

        sig { params(name: String, extras: T::Array[String]).returns(String) }
        def normalised_name(name, extras)
          NameNormaliser.normalise_including_extras(name, extras)
        end

        # Build metadata hash storing extras as a comma-separated string.
        # Stored in metadata so the file updater can reconstruct the full
        # PEP 621 declaration (e.g. "cachecontrol[filecache]>=0.14.0").
        sig { params(extras: T::Array[String]).returns(T::Hash[Symbol, String]) }
        def extras_metadata(extras)
          return {} if extras.empty?

          { extras: extras.join(",") }
        end

        sig do
          params(
            requirements_data: T::Array[PyprojectDocument::PoetryRequirement],
            type: String
          ).returns(T::Array[Dependabot::Dependency::RequirementInput])
        end
        def parse_requirements_from(requirements_data, type)
          requirements_data.filter_map { |requirement| poetry_requirement(requirement, type) }
        end

        sig do
          params(
            requirement: PyprojectDocument::PoetryRequirement,
            type: String
          ).returns(T.nilable(Dependabot::Dependency::RequirementInput))
        end
        def poetry_requirement(requirement, type)
          if requirement.is_a?(String)
            check_requirements(requirement)
            return {
              requirement: requirement,
              file: T.must(pyproject).name,
              source: nil,
              groups: [type]
            }
          end

          return if UNSUPPORTED_DEPENDENCY_TYPES.intersect?(requirement.keys)

          git = requirement_string(requirement, "git")
          tag = requirement_string(requirement, "tag")
          return if git && !tag

          return git_requirement(git, tag, type) if git && tag

          check_requirements(requirement)
          {
            requirement: requirement_string(requirement, "version"),
            file: T.must(pyproject).name,
            source: resolve_source(requirement["source"]),
            groups: [type]
          }
        end

        sig { params(git: String, tag: String, type: String).returns(Dependabot::Dependency::RequirementInput) }
        def git_requirement(git, tag, type)
          {
            requirement: nil,
            file: T.must(pyproject).name,
            source: {
              type: "git",
              url: git,
              ref: tag,
              branch: nil
            },
            groups: [type]
          }
        end

        sig { returns(T::Boolean) }
        def using_poetry?
          pyproject_document.poetry?
        end

        sig { returns(T::Boolean) }
        def using_pep621?
          pyproject_document.pep621?
        end

        sig { returns(T::Boolean) }
        def using_pep735?
          pyproject_document.pep735?
        end

        sig { returns(T::Boolean) }
        def using_pdm?
          using_pep621? && !pdm_lock.nil?
        end

        sig { returns(T::Array[String]) }
        def dynamic_fields
          pyproject_document.dynamic_fields
        end

        sig { params(dep: PepDependency).returns(T::Boolean) }
        def skip_pep621_dep?(dep)
          # If a requirement has a `<` or `<=` marker then updating it is
          # probably blocked. Ignore it.
          return true if dep.markers&.include?("<")

          # If no requirement, don't add it
          requirement = dep.requirement
          raise TypeError, "Python PEP dependency requirement must be a string" unless requirement
          return true if requirement.empty?

          # Skip build-system.requires dependencies when using Poetry
          # Poetry manages its own build system dependencies
          return true if using_poetry? && dep.requirement_type == "build-system.requires"

          # When dependencies or optional-dependencies are listed in project.dynamic,
          # they are managed by the build backend (e.g. Poetry) — skip the PEP 621 path
          dynamic_pep621_dep?(dep.requirement_type)
        end

        sig { params(requirement_type: T.nilable(String)).returns(T::Boolean) }
        def dynamic_pep621_dep?(requirement_type)
          return false unless using_poetry?
          return false unless requirement_type

          if requirement_type == "dependencies"
            dynamic_fields.include?("dependencies")
          elsif pyproject_document.optional_dependency_group?(requirement_type)
            dynamic_fields.include?("optional-dependencies")
          else
            false
          end
        end

        # Create a DependencySet where each element has no requirement. Any
        # requirements will be added when combining the DependencySet with
        # other DependencySets.
        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def lockfile_dependencies
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

          source_types = %w(directory git url)
          poetry_lock_document.packages.each do |package|
            next if source_types.include?(package.source_type)

            name = normalise(package.name)

            dependencies <<
              Dependency.new(
                name: name,
                version: package.version,
                requirements: [],
                package_manager: "pip",
                subdependency_metadata: [{
                  production: production_dependency_names.include?(name)
                }]
              )
          end

          dependencies
        end

        sig { returns(T::Array[T.nilable(String)]) }
        def production_dependency_names
          @production_dependency_names ||= T.let(
            parse_production_dependency_names,
            T.nilable(T::Array[T.nilable(String)])
          )
        end

        sig { returns(T::Array[T.nilable(String)]) }
        def parse_production_dependency_names
          SharedHelpers.in_a_temporary_directory do
            pyproject_file = T.must(pyproject)
            lockfile_file = T.must(lockfile)
            File.write(pyproject_file.name, pyproject_file.content)
            File.write(lockfile_file.name, lockfile_file.content)

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

        sig { params(dep_name: String).returns(T.nilable(String)) }
        def version_from_lockfile(dep_name)
          return unless poetry_lock

          poetry_lock_document.version_for(dep_name) { |name| normalise(name) }
        end

        sig do
          params(req: PyprojectDocument::PoetryRequirement)
            .returns(T::Array[Dependabot::Python::Requirement])
        end
        def check_requirements(req)
          requirement = req.is_a?(String) ? req : requirement_string(req, "version")
          Python::Requirement.requirements_array(requirement)
        rescue Gem::Requirement::BadRequirementError => e
          raise Dependabot::DependencyFileNotEvaluatable, e.message
        end

        sig { params(name: String).returns(String) }
        def normalise(name)
          NameNormaliser.normalise(name)
        end

        sig do
          params(source_value: T.nilable(Object))
            .returns(T.nilable(Dependabot::DependencyRequirement::Source))
        end
        def resolve_source(source_value)
          # Return nil if no source specified
          return nil if source_value.nil?

          # If already a hash, return as-is (handles git sources)
          return PyprojectValueParser.object_hash(source_value, "Poetry dependency source") if source_value.is_a?(Hash)

          # String sources are references to [[tool.poetry.source]] definitions
          # Look up the source definition and create a hash
          return nil unless source_value.is_a?(String)

          source_name = source_value
          source_def = pyproject_document.poetry_source(source_name)

          # If source definition not found, return nil
          return nil unless source_def

          # Create a hash with type and url from the source definition
          # Use "registry" as the type since these are package index sources
          {
            type: "registry",
            url: source_def.url,
            name: source_name
          }
        end

        sig { returns(PyprojectDocument) }
        def pyproject_document
          @pyproject_document ||= PyprojectDocument.from_file(T.must(pyproject))
        end

        sig { returns(PoetryLock) }
        def poetry_lock_document
          @poetry_lock_document ||= PoetryLock.from_file(T.must(poetry_lock))
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pyproject
          @pyproject ||= T.let(
            dependency_files.find { |f| f.name == "pyproject.toml" },
            T.nilable(Dependabot::DependencyFile)
          )
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def lockfile
          poetry_lock
        end

        sig { returns(T::Array[PepDependency]) }
        def parse_pep621_pep735_dependencies
          SharedHelpers.in_a_temporary_directory do
            write_temporary_pyproject

            PepDependency.from_helper_result(
              SharedHelpers.run_helper_subprocess(
                command: "pyenv exec python3 #{NativeHelpers.python_helper_path}",
                function: "parse_pep621_pep735_dependencies",
                args: [T.must(pyproject).name]
              )
            )
          end
        end

        sig { returns(Integer) }
        def write_temporary_pyproject
          path = T.must(pyproject).name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, T.must(pyproject).content)
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def poetry_lock
          @poetry_lock ||= T.let(
            dependency_files.find { |f| f.name == "poetry.lock" },
            T.nilable(Dependabot::DependencyFile)
          )
        end

        sig do
          params(
            requirement: PyprojectValueParser::ObjectHash,
            key: String
          ).returns(T.nilable(String))
        end
        def requirement_string(requirement, key)
          PyprojectValueParser.optional_string(requirement[key], "Poetry dependency #{key}")
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pdm_lock
          @pdm_lock ||= T.let(
            dependency_files.find { |f| f.name == "pdm.lock" },
            T.nilable(Dependabot::DependencyFile)
          )
        end
      end
    end
  end
end
