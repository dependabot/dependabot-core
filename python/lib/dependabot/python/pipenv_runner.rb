# typed: true
# frozen_string_literal: true

require "dependabot/shared_helpers"

module Dependabot
  module Python
    class PipenvRunner
      def initialize(language_version_manager:)
        @language_version_manager = language_version_manager
      end

      def run(command)
        run_command(
          "pyenv local #{language_version_manager.python_major_minor}",
          fingerprint: "pyenv local <python_major_minor>"
        )

        run_command(command)
      end

      private

      attr_reader :language_version_manager

      def run_command(command, fingerprint: nil)
        SharedHelpers.run_shell_command(command, env: pipenv_env_variables, fingerprint: fingerprint)
      end

      def pipenv_env_variables
        {
          "PIPENV_YES" => "true",       # Install new Python ver if needed
          "PIPENV_MAX_RETRIES" => "3",  # Retry timeouts
          "PIPENV_NOSPIN" => "1",       # Don't pollute logs with spinner
          "PIPENV_TIMEOUT" => "600",    # Set install timeout to 10 minutes
          "PIP_DEFAULT_TIMEOUT" => "60" # Set pip timeout to 1 minute
        }
      end
    end
  end
end
