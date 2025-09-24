# typed: strict
# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/python/file_parser"
require "json"
require "sorbet-runtime"

module Dependabot
  module Python
    class PipenvRunner
      extend T::Sig

      sig do
        params(
          dependency: Dependabot::Dependency,
          lockfile: T.nilable(Dependabot::DependencyFile),
          language_version_manager: LanguageVersionManager
        )
          .void
      end
      def initialize(dependency:, lockfile:, language_version_manager:)
        @dependency = dependency
        @lockfile = lockfile
        @language_version_manager = language_version_manager
      end

      sig { params(constraint: T.nilable(String)).returns(String) }
      def run_upgrade(constraint)
        constraint = "" if constraint == "*"
        command = "pyenv exec pipenv upgrade --verbose #{dependency_name}#{constraint}"
        command << " --dev" if lockfile_section == "develop"

        run(command, fingerprint: "pyenv exec pipenv upgrade --verbose <dependency_name><constraint>")
      end

      sig { params(constraint: T.nilable(String)).returns(T.nilable(String)) }
      def run_upgrade_and_fetch_version(constraint)
        run_upgrade(constraint)

        updated_lockfile = JSON.parse(File.read("Pipfile.lock"))

        fetch_version_from_parsed_lockfile(updated_lockfile)
      end

      sig { params(command: String, fingerprint: T.nilable(String)).returns(String) }
      def run(command, fingerprint: nil)
        run_command(
          "pyenv local #{language_version_manager.python_major_minor}",
          fingerprint: "pyenv local <python_major_minor>"
        )

        run_command(command, fingerprint: fingerprint)
      end

      private

      sig { returns(Dependabot::Dependency) }
      attr_reader :dependency

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      attr_reader :lockfile

      sig { returns(LanguageVersionManager) }
      attr_reader :language_version_manager

      sig { params(updated_lockfile: T::Hash[String, T.untyped]).returns(T.nilable(String)) }
      def fetch_version_from_parsed_lockfile(updated_lockfile)
        deps = updated_lockfile[lockfile_section] || {}

        deps.dig(dependency_name, "version")
            &.gsub(/^==/, "")
      end

      sig { params(command: String, fingerprint: T.nilable(String)).returns(String) }
      def run_command(command, fingerprint: nil)
        SharedHelpers.run_shell_command(command, env: pipenv_env_variables, fingerprint: fingerprint)
      end

      sig { returns(String) }
      def lockfile_section
        if dependency.requirements.any?
          T.must(dependency.requirements.first)[:groups].first
        else
          Python::FileParser::DEPENDENCY_GROUP_KEYS.each do |keys|
            section = keys.fetch(:lockfile)
            return section if JSON.parse(T.must(T.must(lockfile).content))[section].keys.any?(dependency_name)
          end
        end
      end

      sig { returns(String) }
      def dependency_name
        dependency.metadata[:original_name] || dependency.name
      end

      sig { returns(T::Hash[String, String]) }
      def pipenv_env_variables
        {
          "PIPENV_YES" => "true",        # Install new Python ver if needed
          "PIPENV_MAX_RETRIES" => "3",   # Retry timeouts
          "PIPENV_NOSPIN" => "1",        # Don't pollute logs with spinner
          "PIPENV_TIMEOUT" => "600",     # Set install timeout to 10 minutes
          "PIP_DEFAULT_TIMEOUT" => "60", # Set pip timeout to 1 minute
          "COLUMNS" => "250"             # Avoid line wrapping
        }
      end
    end
  end
end
