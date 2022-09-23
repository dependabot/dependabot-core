# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    module Helpers
      def self.npm_version(lockfile_content)
        "npm#{npm_version_numeric(lockfile_content)}"
      end

      def self.npm_version_numeric(lockfile_content)
        return 8 unless lockfile_content
        return 8 if JSON.parse(lockfile_content)["lockfileVersion"] >= 2

        6
      rescue JSON::ParserError
        6
      end

      # Run any number of yarn commands while ensuring that `enableScripts` is
      # set to false. Yarn commands should _not_ be ran outside of this helper
      # to ensure that postinstall scripts are never executed, as they could
      # contain malicious code.
      def self.run_yarn_commands(*commands)
        # We never want to execute postinstall scripts
        SharedHelpers.run_shell_command("yarn config set enableScripts false")
        SharedHelpers.run_shell_command("yarn config set httpProxy #{ENV.fetch('HTTP_PROXY', '')}")
        SharedHelpers.run_shell_command("yarn config set httpsProxy #{ENV.fetch('HTTPS_PROXY', '')}")
        commands.each { |cmd| SharedHelpers.run_shell_command(cmd) }
      end
    end
  end
end
