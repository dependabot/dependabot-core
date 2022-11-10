# frozen_string_literal: true

require "dependabot/logger"
require "dependabot/python/version"

module Dependabot
  module Python
    module Helpers
      def self.install_required_python(python_version)
        # The leading space is important in the version check
        return if SharedHelpers.run_shell_command("pyenv versions").include?(" #{python_major_minor(python_version)}.")

        if File.exist?("/usr/local/.pyenv/#{python_major_minor(python_version)}.tar.gz")
          SharedHelpers.run_shell_command(
            "tar xzf /usr/local/.pyenv/#{python_major_minor(python_version)}.tar.gz -C /usr/local/.pyenv/"
          )
          return if SharedHelpers.run_shell_command("pyenv versions").
                    include?(" #{python_major_minor(python_version)}.")
        end

        Dependabot.logger.info("Installing required Python #{python_version}.")
        start = Time.now
        SharedHelpers.run_shell_command("pyenv install -s #{python_version}")
        SharedHelpers.run_shell_command("pyenv exec pip install --upgrade pip")
        SharedHelpers.run_shell_command("pyenv exec pip install -r" \
                                        "#{NativeHelpers.python_requirements_path}")
        time_taken = Time.now - start
        Dependabot.logger.info("Installing Python #{python_version} took #{time_taken}s.")
      end

      def self.python_major_minor(python_version)
        python = Python::Version.new(python_version)
        "#{python.segments[0]}.#{python.segments[1]}"
      end
    end
  end
end
