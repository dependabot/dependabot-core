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

      def self.yarn_version(package_json_content, yarn_lock)
        return @yarn_version if defined?(@yarn_version)

        package = JSON.parse(package_json_content)
        if (package_manager = package.fetch("packageManager", nil))
          get_yarn_version_from_path(package_manager)
        elsif yarn_lock
          1
        end
      end

      def self.get_yarn_version(package_manager)
        version_match = package_manager.match(/yarn@(?<version>\d+.\d+.\d+)/)
        version_match&.named_captures&.fetch("version", nil)
      end

      def self.yarn_berry?
        major_version = Version.new(yarn_version).major
        return true if major_version >= 2
        false
      end

      # Run any number of yarn commands while ensuring that `enableScripts` is
      # set to false. Yarn commands should _not_ be ran outside of this helper
      # to ensure that postinstall scripts are never executed, as they could
      # contain malicious code.
      def self.run_yarn_commands(*commands)
        # We never want to execute postinstall scripts
        SharedHelpers.run_shell_command("yarn config set enableScripts false")
        if (http_proxy = ENV.fetch("HTTP_PROXY", false))
          SharedHelpers.run_shell_command("yarn config set httpProxy #{http_proxy}")
        end
        if (https_proxy = ENV.fetch("HTTPS_PROXY", false))
          SharedHelpers.run_shell_command("yarn config set httpsProxy #{https_proxy}")
        end
        if (ca_file_path = ENV.fetch("NODE_EXTRA_CA_CERTS", false))
          output = SharedHelpers.run_shell_command("yarn --version")
          major_version = Version.new(output).major
          if major_version >= 4
            SharedHelpers.run_shell_command("yarn config set httpsCaFilePath #{ca_file_path}")
          else
            SharedHelpers.run_shell_command("yarn config set caFilePath #{ca_file_path}")
          end
        end
        commands.each { |cmd| SharedHelpers.run_shell_command(cmd) }
      end
    end
  end
end
