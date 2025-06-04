# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"
require "open3"
require "dependabot/dependency"
require "dependabot/shared_helpers"
require "dependabot/python/language_version_manager"
require "dependabot/python/version"
require "dependabot/python/requirement"
require "dependabot/python/file_parser/python_requirement_parser"
require "dependabot/python/file_updater"
require "dependabot/python/native_helpers"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class FileUpdater
      class PoetryFileUpdater
        require_relative "pyproject_preparer"
        extend T::Sig

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependencies:, dependency_files:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
          @updated_dependency_files = T.let(nil, T.nilable(T::Array[Dependabot::DependencyFile]))
          @prepared_pyproject = T.let(nil, T.nilable(String))
          @pyproject = T.let(nil, T.nilable(Dependabot::DependencyFile))
          @lockfile = T.let(nil, T.nilable(Dependabot::DependencyFile))
          @updated_lockfile_content = T.let(nil, T.nilable(String))
          @language_version_manager = T.let(nil, T.nilable(LanguageVersionManager))
          @python_requirement_parser = T.let(nil, T.nilable(FileParser::PythonRequirementParser))
          @updated_pyproject_content = T.let(nil, T.nilable(String))
          @python_helper_path = T.let(nil, T.nilable(String))
          @poetry_lock = T.let(nil, T.nilable(Dependabot::DependencyFile))
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def updated_dependency_files
          @updated_dependency_files ||= fetch_updated_dependency_files
        end

        private

        sig { returns(Dependabot::Dependency) }
        def dependency
          # For now, we'll only ever be updating a single dependency
          T.must(dependencies.first)
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def fetch_updated_dependency_files
          updated_files = []

          if file_changed?(T.must(pyproject))
            updated_files <<
              updated_file(
                file: T.must(pyproject),
                content: T.must(updated_pyproject_content)
              )
          end

          raise "Expected lockfile to change!" if lockfile && lockfile&.content == updated_lockfile_content

          if lockfile
            updated_files <<
              updated_file(file: T.must(lockfile), content: updated_lockfile_content)
          end

          updated_files
        end

        sig { returns(T.nilable(String)) }
        def updated_pyproject_content
          content = T.must(pyproject).content
          return content unless requirement_changed?(T.must(pyproject), dependency)

          updated_content = content.dup

          dependency.requirements.zip(T.must(dependency.previous_requirements)).each do |new_r, old_r|
            next unless new_r[:file] == pyproject&.name && T.must(old_r)[:file] == pyproject&.name

            updated_content = replace_dep(dependency, T.must(updated_content), new_r, T.must(old_r))
          end

          raise DependencyFileContentNotChanged, "Content did not change!" if content == updated_content

          updated_content
        end

        sig do
          params(
            dep: Dependabot::Dependency,
            content: String,
            new_r: T::Hash[Symbol, T.untyped],
            old_r: T::Hash[Symbol, T.untyped]
          ).returns(String)
        end
        def replace_dep(dep, content, new_r, old_r)
          new_req = new_r[:requirement]
          old_req = old_r[:requirement]

          declaration_regex = declaration_regex(dep, old_r)
          declaration_match = content.match(declaration_regex)
          if declaration_match
            declaration = declaration_match[:declaration]
            new_declaration = T.must(declaration).sub(old_req, new_req)
            content.sub(T.must(declaration), new_declaration)
          else
            content.gsub(table_declaration_regex(dep, new_r)) do |match|
              match.gsub(/(\s*version\s*=\s*["'])#{Regexp.escape(old_req)}/,
                         '\1' + new_req)
            end
          end
        end

        sig { returns(String) }
        def updated_lockfile_content
          @updated_lockfile_content ||=
            begin
              new_lockfile = updated_lockfile_content_for(prepared_pyproject)

              original_locked_python = TomlRB.parse(T.must(lockfile).content)["metadata"]["python-versions"]

              new_lockfile.gsub!(/\[metadata\]\n.*python-versions[^\n]+\n/m) do |match|
                match.gsub(/(["']).*(['"])\n\Z/, '\1' + original_locked_python + '\1' + "\n")
              end

              tmp_hash =
                TomlRB.parse(new_lockfile)["metadata"]["content-hash"]
              correct_hash = pyproject_hash_for(updated_pyproject_content.to_s)

              new_lockfile.gsub(tmp_hash, T.must(correct_hash).to_s)
            end
        end

        sig { returns(String) }
        def prepared_pyproject
          @prepared_pyproject ||=
            begin
              content = updated_pyproject_content
              content = sanitize(T.must(content))
              content = freeze_other_dependencies(content)
              content = freeze_dependencies_being_updated(content)
              content = update_python_requirement(content)
              content
            end
        end

        sig { params(pyproject_content: String).returns(String) }
        def freeze_other_dependencies(pyproject_content)
          PyprojectPreparer
            .new(pyproject_content: pyproject_content, lockfile: lockfile)
            .freeze_top_level_dependencies_except(dependencies)
        end

        sig { params(pyproject_content: String).returns(String) }
        def freeze_dependencies_being_updated(pyproject_content)
          pyproject_object = TomlRB.parse(pyproject_content)
          poetry_object = pyproject_object.fetch("tool").fetch("poetry")

          dependencies.each do |dep|
            if dep.requirements.find { |r| r[:file] == pyproject&.name }
              lock_declaration_to_new_version!(poetry_object, dep)
            else
              create_declaration_at_new_version!(poetry_object, dep)
            end
          end

          TomlRB.dump(pyproject_object)
        end

        sig { params(pyproject_content: String).returns(String) }
        def update_python_requirement(pyproject_content)
          PyprojectPreparer
            .new(pyproject_content: pyproject_content)
            .update_python_requirement(language_version_manager.python_version)
        end

        sig { params(poetry_object: T::Hash[String, T.untyped], dep: Dependabot::Dependency).returns(T::Array[String]) }
        def lock_declaration_to_new_version!(poetry_object, dep)
          Dependabot::Python::FileParser::PyprojectFilesParser::POETRY_DEPENDENCY_TYPES.each do |type|
            names = poetry_object[type]&.keys || []
            pkg_name = names.find { |nm| normalise(nm) == dep.name }
            next unless pkg_name

            if poetry_object[type][pkg_name].is_a?(Hash)
              poetry_object[type][pkg_name]["version"] = dep.version
            else
              poetry_object[type][pkg_name] = dep.version
            end
          end
        end

        sig { params(poetry_object: T::Hash[String, T.untyped], dep: Dependabot::Dependency).void }
        def create_declaration_at_new_version!(poetry_object, dep)
          subdep_type = dep.production? ? "dependencies" : "dev-dependencies"

          poetry_object[subdep_type] ||= {}
          poetry_object[subdep_type][dep.name] = dep.version
        end

        sig { params(pyproject_content: String).returns(String) }
        def sanitize(pyproject_content)
          PyprojectPreparer
            .new(pyproject_content: pyproject_content)
            .sanitize
        end

        sig { params(pyproject_content: String).returns(String) }
        def updated_lockfile_content_for(pyproject_content)
          SharedHelpers.in_a_temporary_directory do
            SharedHelpers.with_git_configured(credentials: credentials) do
              write_temporary_dependency_files(pyproject_content)
              add_auth_env_vars

              language_version_manager.install_required_python

              # use system git instead of the pure Python dulwich
              run_poetry_command("pyenv exec poetry config system-git-client true")

              run_poetry_update_command

              File.read("poetry.lock")
            end
          end
        end

        # Using `--lock` avoids doing an install.
        # Using `--no-interaction` avoids asking for passwords.
        sig { returns(String) }
        def run_poetry_update_command
          run_poetry_command(
            "pyenv exec poetry update #{dependency.name} --lock --no-interaction",
            fingerprint: "pyenv exec poetry update <dependency_name> --lock --no-interaction"
          )
        end

        sig { params(command: String, fingerprint: T.nilable(String)).returns(String) }
        def run_poetry_command(command, fingerprint: nil)
          SharedHelpers.run_shell_command(command, fingerprint: fingerprint)
        end

        sig { params(pyproject_content: Object).returns(Integer) }
        def write_temporary_dependency_files(pyproject_content)
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end

          # Overwrite the .python-version with updated content
          File.write(".python-version", language_version_manager.python_major_minor)

          # Overwrite the pyproject with updated content
          File.write("pyproject.toml", pyproject_content)
        end

        sig { void }
        def add_auth_env_vars
          Python::FileUpdater::PyprojectPreparer
            .new(pyproject_content: T.must(pyproject&.content))
            .add_auth_env_vars(credentials)
        end

        sig do
          params(
            pyproject_content: String
          ).returns(T.nilable(T.any(
                                T::Hash[String, T.untyped],
                                String,
                                T::Array[T::Hash[String, T.untyped]]
                              )))
        end
        def pyproject_hash_for(pyproject_content)
          SharedHelpers.in_a_temporary_directory do |dir|
            SharedHelpers.with_git_configured(credentials: credentials) do
              write_temporary_dependency_files(pyproject_content)

              SharedHelpers.run_helper_subprocess(
                command: "pyenv exec python3 #{python_helper_path}",
                function: "get_pyproject_hash",
                args: [T.cast(dir, Pathname).to_s]
              )
            end
          end
        end

        sig { params(dep: Dependabot::Dependency, old_req: T::Hash[Symbol, T.untyped]).returns(Regexp) }
        def declaration_regex(dep, old_req)
          group = old_req[:groups].first

          header_regex = "#{group}(?:\\.dependencies)?\\]\s*(?:\s*#.*?)*?"
          /#{header_regex}\n.*?(?<declaration>(?:^\s*|["'])#{escape(dep)}["']?\s*=[^\n]*)$/mi
        end

        sig { params(dep: Dependabot::Dependency, old_req: T::Hash[Symbol, T.untyped]).returns(Regexp) }
        def table_declaration_regex(dep, old_req)
          /tool\.poetry\.#{old_req[:groups].first}\.#{escape(dep)}\]\n.*?\s*version\s* =.*?\n/m
        end

        sig { params(dep: Dependency).returns(String) }
        def escape(dep)
          Regexp.escape(dep.name).gsub("\\-", "[-_.]")
        end

        sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
        def file_changed?(file)
          dependencies.any? { |dep| requirement_changed?(file, dep) }
        end

        sig { params(file: Dependabot::DependencyFile, dependency: Dependabot::Dependency).returns(T::Boolean) }
        def requirement_changed?(file, dependency)
          changed_requirements =
            dependency.requirements - T.must(dependency.previous_requirements)

          changed_requirements.any? { |f| f[:file] == file.name }
        end

        sig { params(file: Dependabot::DependencyFile, content: String).returns(Dependabot::DependencyFile) }
        def updated_file(file:, content:)
          updated_file = file.dup
          updated_file.content = content
          updated_file
        end

        sig { params(name: String).returns(String) }
        def normalise(name)
          NameNormaliser.normalise(name)
        end

        sig { returns(FileParser::PythonRequirementParser) }
        def python_requirement_parser
          @python_requirement_parser ||=
            FileParser::PythonRequirementParser.new(
              dependency_files: dependency_files
            )
        end

        sig { returns(Dependabot::Python::LanguageVersionManager) }
        def language_version_manager
          @language_version_manager ||=
            LanguageVersionManager.new(
              python_requirement_parser: python_requirement_parser
            )
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pyproject
          @pyproject ||=
            dependency_files.find { |f| f.name == "pyproject.toml" }
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def lockfile
          @lockfile ||= poetry_lock
        end

        sig { returns(String) }
        def python_helper_path
          NativeHelpers.python_helper_path
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def poetry_lock
          dependency_files.find { |f| f.name == "poetry.lock" }
        end
      end
    end
  end
end
