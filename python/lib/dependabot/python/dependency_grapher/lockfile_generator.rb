# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/shared_helpers"
require "dependabot/python/file_parser/python_requirement_parser"
require "dependabot/python/language_version_manager"
require "dependabot/python/poetry_plugin_installer"

module Dependabot
  module Python
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      class LockfileGenerator
        extend T::Sig

        LOCKFILE_NAME = "poetry.lock"

        sig do
          params(
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency_files:, credentials:)
          @dependency_files = dependency_files
          @credentials = credentials
        end

        sig { returns(Dependabot::DependencyFile) }
        def generate
          SharedHelpers.in_a_temporary_directory do
            SharedHelpers.with_git_configured(credentials: credentials) do
              write_temporary_files
              language_version_manager.install_required_python

              # Install any required Poetry plugins declared in pyproject.toml
              poetry_plugin_installer.install_required_plugins

              run_poetry_lock
              read_generated_lockfile
            end
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_generation_error(e)
          raise
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { void }
        def write_temporary_files
          dependency_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, file.content)
          end

          File.write(".python-version", language_version_manager.python_major_minor)
        end

        sig { void }
        def run_poetry_lock
          Dependabot.logger.info("Generating poetry.lock for dependency graphing")

          # Use system git instead of the pure Python dulwich
          run_poetry_command("pyenv exec poetry config system-git-client true")

          # --no-interaction avoids password prompts
          run_poetry_command("pyenv exec poetry lock --no-interaction")
        end

        sig { returns(Dependabot::DependencyFile) }
        def read_generated_lockfile
          unless File.exist?(LOCKFILE_NAME)
            Dependabot.logger.error("#{LOCKFILE_NAME} was not generated")
            raise Dependabot::DependencyFileNotEvaluatable.new("#{LOCKFILE_NAME} was not generated")
          end

          content = File.read(LOCKFILE_NAME)

          Dependabot::DependencyFile.new(
            name: LOCKFILE_NAME,
            content: content,
            directory: pyproject_directory
          )
        end

        sig { returns(String) }
        def pyproject_directory
          pyproject = dependency_files.find { |f| f.name == "pyproject.toml" }
          pyproject&.directory || "/"
        end

        sig { params(command: String).returns(String) }
        def run_poetry_command(command)
          SharedHelpers.run_shell_command(command, fingerprint: command)
        end

        sig { returns(LanguageVersionManager) }
        def language_version_manager
          @language_version_manager ||= T.let(
            LanguageVersionManager.new(
              python_requirement_parser: python_requirement_parser
            ),
            T.nilable(LanguageVersionManager)
          )
        end

        sig { returns(FileParser::PythonRequirementParser) }
        def python_requirement_parser
          @python_requirement_parser ||= T.let(
            FileParser::PythonRequirementParser.new(
              dependency_files: dependency_files
            ),
            T.nilable(FileParser::PythonRequirementParser)
          )
        end

        sig { returns(PoetryPluginInstaller) }
        def poetry_plugin_installer
          @poetry_plugin_installer ||= T.let(
            PoetryPluginInstaller.from_dependency_files(dependency_files),
            T.nilable(PoetryPluginInstaller)
          )
        end

        sig { params(error: SharedHelpers::HelperSubprocessFailed).void }
        def handle_generation_error(error)
          Dependabot.logger.error(
            "Failed to generate #{LOCKFILE_NAME}: #{error.message}"
          )
        end
      end
    end
  end
end
