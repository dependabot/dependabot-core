# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    module NativeHelpers
      extend T::Sig

      sig { returns(String) }
      def self.helper_path
        "node #{File.join(native_helpers_root, 'dist', 'run.js')}"
      end

      sig { returns(String) }
      def self.native_helpers_root
        helpers_root = ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", nil)
        return File.join(helpers_root, "npm_and_yarn") unless helpers_root.nil?

        File.join(__dir__, "../../../helpers")
      end

      sig { params(dependency_names: T::Array[String]).returns(String) }
      def self.run_npm8_subdependency_update_command(dependency_names)
        # NOTE: npm options
        # - `--force` ignores checks for platform (os, cpu) and engines
        # - `--ignore-scripts` disables prepare and prepack scripts which are run
        #   when installing git dependencies
        command = [
          "update",
          *dependency_names,
          "--force",
          "--ignore-scripts",
          "--package-lock-only"
        ].join(" ")

        fingerprint = [
          "update",
          "<dependency_names>",
          "--force",
          "--ignore-scripts",
          "--package-lock-only"
        ].join(" ")

        Helpers.run_npm_command(command, fingerprint: fingerprint)
      end

      sig { returns(String) }
      def self.run_npm_audit_fix_command
        # Fallback for transitive dependencies in workspace repos where
        # `npm update` is a no-op because the package isn't in package.json.
        # `npm audit fix` updates all fixable vulnerabilities in the lockfile.
        command = "audit fix --package-lock-only --ignore-scripts"
        fingerprint = "audit fix --package-lock-only --ignore-scripts"

        Helpers.run_npm_command(command, fingerprint: fingerprint)
      end

      sig { returns(String) }
      def self.run_pnpm_audit_fix_command
        # Fallback for transitive dependencies where `pnpm update` is a no-op.
        # `pnpm audit --fix` adds overrides to the manifest for vulnerable deps.
        Helpers.run_pnpm_command(
          "audit --fix",
          fingerprint: "audit --fix"
        )
      end

      sig { returns(String) }
      def self.run_yarn_audit_fix_command
        # Fallback for transitive dependencies where `yarn up -R` is a no-op.
        # `yarn npm audit --fix` updates vulnerable deps in the lockfile.
        Helpers.run_yarn_command(
          "npm audit --fix --mode update-lockfile",
          fingerprint: "npm audit --fix --mode update-lockfile"
        )
      end
    end
  end
end
