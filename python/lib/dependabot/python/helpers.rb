# frozen_string_literal: true
require "dependabot/logger"

module Dependabot
  module Python
    module Helpers
      def self.install_required_python(python_version)
        # The leading space is important in the version check
        return if SharedHelpers.run_shell_command("pyenv versions").include?(" #{python_version}")

        Dependabot.logger.info("Installing required Python #{python_version}.")
        SharedHelpers.run_shell_command("pyenv install -s #{python_version}")
        SharedHelpers.run_shell_command("pyenv exec pip install --upgrade pip")
        SharedHelpers.run_shell_command("pyenv exec pip install -r" \
                                        "#{NativeHelpers.python_requirements_path}")
      end
    end
  end
end
