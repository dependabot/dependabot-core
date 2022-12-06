# frozen_string_literal: true

module Dependabot
  module NpmAndYarn
    module NativeHelpers
      def self.helper_path
        "node #{File.join(native_helpers_root, 'run.js')}"
      end

      def self.native_helpers_root
        helpers_root = ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", nil)
        return File.join(helpers_root, "npm_and_yarn") unless helpers_root.nil?

        File.join(__dir__, "../../../helpers")
      end

      def self.run_npm8_subdependency_update_command(dependency_names)
        # NOTE: npm options
        # - `--force` ignores checks for platform (os, cpu) and engines
        # - `--dry-run=false` the updater sets a global .npmrc with dry-run: true to
        #   work around an issue in npm 6, we don't want that here
        # - `--ignore-scripts` disables prepare and prepack scripts which are run
        #   when installing git dependencies
        command = [
          "npm",
          "update",
          *dependency_names,
          "--force",
          "--dry-run",
          "false",
          "--ignore-scripts",
          "--package-lock-only"
        ].join(" ")

        fingerprint = [
          "npm",
          "update",
          "<dependency_names>",
          "--force",
          "--dry-run",
          "false",
          "--ignore-scripts",
          "--package-lock-only"
        ].join(" ")

        SharedHelpers.run_shell_command(command, fingerprint: fingerprint)
      end
    end
  end
end
