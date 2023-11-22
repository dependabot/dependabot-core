# typed: true
# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/python/file_parser"
require "json"

module Dependabot
  module Python
    class PipenvRunner
      def initialize(dependency:, lockfile:, language_version_manager:)
        @dependency = dependency
        @lockfile = lockfile
        @language_version_manager = language_version_manager
      end

      def run_upgrade(constraint)
        constraint = "" if constraint == "*"
        command = "pyenv exec pipenv upgrade --verbose #{dependency_name}#{constraint}"
        command << " --dev" if lockfile_section == "develop"

        run(command, fingerprint: "pyenv exec pipenv upgrade --verbose <dependency_name><constraint>")
      end

      def run_upgrade_and_fetch_version(constraint)
        run_upgrade(constraint)

        updated_lockfile = JSON.parse(File.read("Pipfile.lock"))

        fetch_version_from_parsed_lockfile(updated_lockfile)
      end

      def run(command, fingerprint: nil)
        run_command(
          "pyenv local #{language_version_manager.python_major_minor}",
          fingerprint: "pyenv local <python_major_minor>"
        )

        run_command(command, fingerprint: fingerprint)
      end

      private

      attr_reader :dependency, :lockfile, :language_version_manager

      def fetch_version_from_parsed_lockfile(updated_lockfile)
        deps = updated_lockfile[lockfile_section] || {}

        deps.dig(dependency_name, "version")
            &.gsub(/^==/, "")
      end

      def run_command(command, fingerprint: nil)
        SharedHelpers.run_shell_command(command, env: pipenv_env_variables, fingerprint: fingerprint)
      end

      def lockfile_section
        if dependency.requirements.any?
          dependency.requirements.first[:groups].first
        else
          Python::FileParser::DEPENDENCY_GROUP_KEYS.each do |keys|
            section = keys.fetch(:lockfile)
            return section if JSON.parse(lockfile.content)[section].keys.any?(dependency_name)
          end
        end
      end

      def dependency_name
        dependency.metadata[:original_name] || dependency.name
      end

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
