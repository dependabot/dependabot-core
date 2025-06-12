# typed: strict
# frozen_string_literal: true

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
      class PdmFileUpdater
        extend T::Sig
        require_relative "pyproject_preparer"

        REQUIRED_FILES = %w(pyproject.toml pdm.lock).freeze

        sig { returns(T::Array[Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig do
          params(
            dependencies: T::Array[Dependency],
            dependency_files: T::Array[DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependencies:, dependency_files:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @credentials = credentials
          @prepared_pyproject = T.let(nil, T.nilable(String))
          @updated_lockfile_content = T.let(nil, T.nilable(String))
          @pyproject = T.let(nil, T.nilable(Dependabot::DependencyFile))
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def updated_dependency_files
          @updated_dependency_files ||= T.let(fetch_updated_dependency_files,
                                              T.nilable(T::Array[Dependabot::DependencyFile]))
        end

        private

        sig { returns(T.nilable(Dependabot::Dependency)) }
        def dependency
          # For now, we'll only ever be updating a single dependency
          T.must(dependencies.first)
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def fetch_updated_dependency_files
          return [] unless create_or_update_lock_file?

          updated_files = []

          if file_changed?(pyproject)
            updated_files <<
              updated_file(
                file: T.must(pyproject),
                content: T.must(updated_pyproject_content)
              )
          end

          if lockfile
            # Use updated_lockfile_content which might raise if the lockfile doesn't change
            new_content = updated_lockfile_content
            raise "Expected lockfile to change!" if file_changed?(pyproject) && T.must(lockfile).content == new_content

            updated_files << updated_file(file: T.must(lockfile), content: new_content)
          end

          updated_files
        end

        sig { returns(T.nilable(String)) }
        def updated_pyproject_content
          content = T.must(pyproject).content
          return content unless file_changed?(T.must(pyproject))

          updated_content = content.dup

          T.must(dependency).requirements.zip(T.must(T.must(dependency).previous_requirements)).each do |new_r, old_r|
            next unless new_r[:file] == T.must(pyproject).name && T.must(old_r)[:file] == T.must(pyproject).name

            updated_content = replace_dep(T.must(dependency), T.must(updated_content), new_r, T.must(old_r))
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
            content
          end
        end

        sig { returns(String) }
        def updated_lockfile_content
          @updated_lockfile_content ||=
            begin
              new_lockfile = updated_lockfile_content_for(prepared_pyproject)
              # Correct the content hash in lockfile
              tmp_hash =
                TomlRB.parse(new_lockfile)["metadata"]["content_hash"]
              correct_hash = pyproject_hash_for(updated_pyproject_content.to_s)
              new_lockfile = new_lockfile.gsub(tmp_hash, correct_hash.to_s) if tmp_hash != correct_hash
              # Normalize line endings to ensure proper comparison
              normalize_line_endings(new_lockfile, T.must(lockfile&.content))
            end
        end

        sig { params(content: String).returns(String) }
        def pyproject_hash_for(content)
          SharedHelpers.in_a_temporary_directory do |dir|
            write_temporary_dependency_files(content)

            SharedHelpers.run_helper_subprocess(
              command: "pyenv exec python3 #{python_helper_path}",
              function: "get_pdm_project_hash",
              args: [T.cast(dir, Pathname).to_s]
            )
          end
        end
        # Helper method to normalize line endings between two strings
        sig { params(content: String, reference: String).returns(String) }
        def normalize_line_endings(content, reference)
          # Check if reference has escaped newlines like "\n" +
          if reference.include?("\\n")
            content.gsub("\n", "\\n")
          else
            content
          end
        end

        sig { returns(String) }
        def prepared_pyproject
          @prepared_pyproject ||=
            begin
              content = updated_pyproject_content
              content = sanitize(T.must(content))
              content
            end
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

              # Set up Python environment using LanguageVersionManager
              setup_python_environment

              run_update_command

              File.read("pdm.lock")
            end
          end
        end

        sig { returns(T.nilable(String)) }
        def run_update_command
          # Use pyenv exec to ensure we're using the correct Python environment
          command = "pyenv exec pdm --non-interactive update --update-reuse --no-sync #{T.must(dependency).name}"
          if T.must(dependency&.requirements).any?
            groups = T.must(dependency&.requirements&.first)[:groups]
            command << " --group #{groups.first}" unless groups.empty?
          end
          fingerprint = command.sub(T.must(dependency).name, "<dependency_name>")

          run_command(command, fingerprint: fingerprint)
        end

        sig { params(command: String, fingerprint: T.nilable(String)).returns(String) }
        def run_command(command, fingerprint: nil)
          Dependabot.logger.info("Running command: #{command}")
          SharedHelpers.run_shell_command(command, fingerprint: fingerprint)
        end

        sig { params(pyproject_content: String).returns(Integer) }
        def write_temporary_dependency_files(pyproject_content)
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, file.content)
          end

          # Overwrite the pyproject with updated content
          File.write("pyproject.toml", pyproject_content)
        end

        sig { void }
        def setup_python_environment
          # Use LanguageVersionManager to determine and install the appropriate Python version
          Dependabot.logger.info("Setting up Python environment using LanguageVersionManager")

          begin
            # Install the required Python version
            language_version_manager.install_required_python

            # Set the local Python version
            python_version = language_version_manager.python_version
            Dependabot.logger.info("Setting Python version to #{python_version}")
            SharedHelpers.run_shell_command("pyenv local #{python_version}")
          end
        end

        sig { params(dep: T.untyped, old_req: T.untyped).returns(Regexp) }
        def declaration_regex(dep, old_req)
          escaped_name = Regexp.escape(dep.name)
          # Extract the requirement operator and version
          operator = old_req.fetch(:requirement).match(/^(.+?)[0-9]/)&.captures&.first
          # Escape special regex characters in the operator
          escaped_operator = Regexp.escape(operator) if operator

          # Match various formats of dependency declarations:
          # 1. "dependency==1.0.0" (with quotes around the entire string)
          # 2. dependency==1.0.0 (without quotes)
          # The declaration should only include the package name, operator, and version
          # without the enclosing quotes
          /
            ["']?(?<declaration>#{escaped_name}\s*#{escaped_operator}[\d\.\*]+)["']?
          /x
        end

        sig { params(name: T.any(String, Symbol)).returns(String) }
        def escape(name)
          Regexp.escape(name).gsub("\\-", "[-_.]")
        end

        sig { params(file: T.nilable(DependencyFile)).returns(T::Boolean) }
        def file_changed?(file)
          return false unless file

          dependencies.any? do |dep|
            dep.requirements.any? { |r| r[:file] == file.name } &&
              requirement_changed?(file, dep)
          end
        end

        sig do
          params(file: T.nilable(DependencyFile), dependency: Dependency)
            .returns(T::Boolean)
        end
        def requirement_changed?(file, dependency)
          changed_requirements =
            dependency.requirements - T.must(dependency.previous_requirements)

          changed_requirements.any? { |f| f[:file] == T.must(file).name }
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

        sig { returns(Dependabot::Python::FileParser::PythonRequirementParser) }
        def python_requirement_parser
          @python_requirement_parser ||= T.let(
            FileParser::PythonRequirementParser.new(
              dependency_files: dependency_files
            ), T.nilable(FileParser::PythonRequirementParser)
          )
        end

        sig { returns(Dependabot::Python::LanguageVersionManager) }
        def language_version_manager
          @language_version_manager ||= T.let(
            LanguageVersionManager.new(
              python_requirement_parser: python_requirement_parser
            ), T.nilable(LanguageVersionManager)
          )
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pyproject
          @pyproject ||= T.let(dependency_files.find { |f| f.name == "pyproject.toml" },
                               T.nilable(Dependabot::DependencyFile))
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def lockfile
          @lockfile ||= T.let(pdm_lock, T.nilable(Dependabot::DependencyFile))
        end

        sig { returns(String) }
        def python_helper_path
          NativeHelpers.python_helper_path
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pdm_lock
          dependency_files.find { |f| f.name == "pdm.lock" }
        end

        sig { returns(T::Boolean) }
        def create_or_update_lock_file?
          T.must(dependency).requirements.select { _1[:file].end_with?(*REQUIRED_FILES) }.any?
        end
      end
    end
  end
end
