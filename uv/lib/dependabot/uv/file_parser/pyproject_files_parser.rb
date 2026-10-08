# typed: strong
# frozen_string_literal: true

require "toml-rb"

require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/uv/file_parser"
require "dependabot/uv/requirement"
require "dependabot/errors"
require "dependabot/uv/name_normaliser"
require "dependabot/python/file_parser/pep_dependency"
require "dependabot/python/file_parser/poetry_lock"
require "dependabot/python/file_parser/pyproject_document"

module Dependabot
  module Uv
    class FileParser
      class PyprojectFilesParser
        extend T::Sig

        PepDependency = Dependabot::Python::FileParser::PepDependency
        PoetryLock = Dependabot::Python::FileParser::PoetryLock
        PyprojectDocument = Dependabot::Python::FileParser::PyprojectDocument

        POETRY_DEPENDENCY_TYPES = %w(dependencies dev-dependencies).freeze

        # https://python-poetry.org/docs/dependency-specification/
        UNSUPPORTED_DEPENDENCY_TYPES = %w(git path url).freeze

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
          dependency_set += workspace_member_dependencies if workspace_member_pyproject_files.any?
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
            pep621_pep735_dependencies(T.must(pyproject))
          end
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

        sig { params(pyproject_file: Dependabot::DependencyFile).returns(Dependabot::FileParsers::Base::DependencySet) }
        def pep621_pep735_dependencies(pyproject_file)
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

          # PDM is not yet supported, so we want to ignore it for now because in
          # the current state of things, going on would result in updating
          # pyproject.toml but leaving pdm.lock out of sync, which is
          # undesirable. Leave PDM alone until properly supported
          return dependencies if using_pdm?

          unresolvable_sources = PyprojectDocument.from_file(pyproject_file)
                                                  .unresolvable_uv_source_names
                                                  .map { |name| normalise(name) }

          parse_pep621_pep735_dependencies(pyproject_file).each do |dep|
            # If a requirement has a `<` or `<=` marker then updating it is
            # probably blocked. Ignore it.
            next if dep.markers&.include?("<")

            next if unresolvable_sources.include?(normalise(dep.name))

            # In uv no constraint means any version is acceptable
            requirement_value = dep.requirement == "" ? "*" : dep.requirement

            dependencies <<
              Dependency.new(
                name: normalised_name(dep.name, dep.extras),
                version: dep.version&.include?("*") ? nil : dep.version,
                requirements: [{
                  requirement: requirement_value,
                  file: Pathname.new(dep.file).cleanpath.to_path,
                  source: nil,
                  groups: [dep.requirement_type].compact
                }],
                package_manager: "uv"
              )
          end

          dependencies
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def workspace_member_pyproject_files
          return [] if workspace_member_patterns.empty?

          dependency_files.select do |file|
            next false unless file.support_file? && file.name.end_with?("pyproject.toml")

            workspace_member_file?(file)
          end
        end

        # Only pyprojects declared under `[tool.uv.workspace].members` in the root
        # manifest are true workspace members whose requirements should be updated.
        # Editable `[tool.uv.sources]` path dependencies are separate packages that
        # are fetched as support files for resolution but must not be modified.
        sig { returns(T::Array[String]) }
        def workspace_member_patterns
          workspace_globs("members")
        end

        # uv removes paths matching `[tool.uv.workspace].exclude` after expanding
        # `members`, so an excluded directory is not a workspace member even when it
        # matches a `members` glob.
        sig { returns(T::Array[String]) }
        def workspace_exclude_patterns
          workspace_globs("exclude")
        end

        sig { params(key: String).returns(T::Array[String]) }
        def workspace_globs(key)
          return [] unless pyproject

          pyproject_document.workspace_globs(key)
        end

        sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
        def workspace_member_file?(file)
          member_dir = File.dirname(file.name)

          return false if workspace_exclude_patterns.any? { |pattern| glob_matches_dir?(pattern, member_dir) }

          workspace_member_patterns.any? { |pattern| glob_matches_dir?(pattern, member_dir) }
        end

        sig { params(pattern: String, dir: String).returns(T::Boolean) }
        def glob_matches_dir?(pattern, dir)
          normalized_pattern = pattern.gsub(%r{^\./}, "").chomp("/")
          File.fnmatch?(normalized_pattern, dir, File::FNM_PATHNAME)
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def workspace_member_dependencies
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

          workspace_member_pyproject_files.each do |pyproject_file|
            dependencies += pep621_pep735_dependencies(pyproject_file)
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
              package_manager: "uv"
            )
          end
          dependencies
        end

        sig { params(name: String, extras: T::Array[String]).returns(String) }
        def normalised_name(name, extras)
          NameNormaliser.normalise_including_extras(name, extras)
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

          check_requirements(requirement)
          {
            requirement: requirement_string(requirement, "version"),
            file: T.must(pyproject).name,
            source: poetry_source(requirement["source"]),
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
            .returns(T::Array[Dependabot::Uv::Requirement])
        end
        def check_requirements(req)
          requirement = req.is_a?(String) ? req : requirement_string(req, "version")
          Uv::Requirement.requirements_array(requirement)
        rescue Gem::Requirement::BadRequirementError => e
          raise Dependabot::DependencyFileNotEvaluatable, e.message
        end

        sig { params(name: String).returns(String) }
        def normalise(name)
          NameNormaliser.normalise(name)
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

        sig { params(pyproject_file: Dependabot::DependencyFile).returns(T::Array[PepDependency]) }
        def parse_pep621_pep735_dependencies(pyproject_file)
          SharedHelpers.in_a_temporary_directory do
            write_temporary_pyproject(pyproject_file)

            PepDependency.from_helper_result(
              SharedHelpers.run_helper_subprocess(
                command: "pyenv exec python3 #{NativeHelpers.python_helper_path}",
                function: "parse_pep621_pep735_dependencies",
                args: [pyproject_file.name]
              )
            )
          end
        end

        sig { params(pyproject_file: Dependabot::DependencyFile).returns(Integer) }
        def write_temporary_pyproject(pyproject_file)
          path = pyproject_file.name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, pyproject_file.content)
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
            requirement: T::Hash[String, Object],
            key: String
          ).returns(T.nilable(String))
        end
        def requirement_string(requirement, key)
          value = requirement[key]
          return if value.nil?
          return value if value.is_a?(String)

          raise TypeError, "Poetry dependency #{key} must be a string or nil"
        end

        sig { params(value: T.nilable(Object)).returns(T.nilable(Dependabot::DependencyRequirement::Source)) }
        def poetry_source(value)
          return if value.nil?
          return value if value.is_a?(String)
          raise TypeError, "Poetry dependency source must be a string, object, or nil" unless value.is_a?(Hash)

          source = T.let({}, Dependabot::DependencyRequirement::ObjectHash)
          value.each do |raw_key, raw_value|
            key = T.cast(raw_key, Object)
            raise TypeError, "Poetry dependency source keys must be strings" unless key.is_a?(String)

            source[key] = T.cast(raw_value, Object)
          end
          source
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
