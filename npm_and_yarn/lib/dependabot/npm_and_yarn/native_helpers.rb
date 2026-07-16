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

      sig do
        params(dependency_names: T::Array[String], min_release_age_arg: T.nilable(String)).returns(String)
      end
      def self.run_npm8_subdependency_update_command(dependency_names, min_release_age_arg: nil)
        # NOTE: npm options
        # - `--force` ignores checks for platform (os, cpu) and engines
        # - `--ignore-scripts` disables prepare and prepack scripts which are run
        #   when installing git dependencies
        command_args = [
          "update",
          *dependency_names,
          "--force",
          "--ignore-scripts",
          "--package-lock-only"
        ]
        # Apply the effective release-age gate: `=0` bypasses any `.npmrc` gate for
        # security fixes, a positive value enforces the dependabot.yml cooldown
        # floor on transitive updates. nil leaves npm's own resolution untouched.
        command_args << min_release_age_arg if min_release_age_arg
        command = command_args.join(" ")

        fingerprint_args = [
          "update",
          "<dependency_names>",
          "--force",
          "--ignore-scripts",
          "--package-lock-only"
        ]
        fingerprint_args << fingerprint_min_release_age_arg(min_release_age_arg) if min_release_age_arg
        fingerprint = fingerprint_args.join(" ")

        Helpers.run_npm_command(command, fingerprint: fingerprint)
      end

      sig { params(min_release_age_arg: T.nilable(String)).returns(String) }
      def self.run_npm_audit_fix_command(min_release_age_arg: nil)
        # Fallback for transitive dependencies in workspace repos where
        # `npm update` is a no-op because the package isn't in package.json.
        # `npm audit fix` updates all fixable vulnerabilities in the lockfile.
        # `--force` ignores checks for platform (os, cpu) and engines,
        # matching the flags used by run_npm8_subdependency_update_command.
        command = "audit fix --force --package-lock-only --ignore-scripts"
        # Apply the effective release-age gate (see run_npm8_subdependency_update_command).
        command += " #{min_release_age_arg}" if min_release_age_arg
        fingerprint = "audit fix --force --package-lock-only --ignore-scripts"
        fingerprint += " #{fingerprint_min_release_age_arg(min_release_age_arg)}" if min_release_age_arg

        Helpers.run_npm_command(command, fingerprint: fingerprint)
      end

      # Masks the varying cooldown day count out of the telemetry fingerprint while
      # keeping the security `=0` bypass distinguishable (mirrors the npm lockfile
      # updater's `fingerprint_min_release_age_arg`).
      sig { params(arg: String).returns(String) }
      def self.fingerprint_min_release_age_arg(arg)
        arg == "--min-release-age=0" ? arg : "--min-release-age=<days>"
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

      sig { params(dependency_name: String, recursive: T::Boolean).returns([String, String]) }
      def self.pnpm_deep_update_command(dependency_name, recursive: false)
        # `pnpm update --depth Infinity <dep>` traverses the full dependency
        # graph, allowing transitive dependencies to be updated in the lockfile
        # without modifying any package.json (unlike `pnpm audit --fix`).
        # `-r --include-workspace-root` is required for workspace repos so the
        # update is applied across all packages.
        flags = recursive ? "-r --include-workspace-root " : ""
        cmd = "#{flags}update #{dependency_name} --depth Infinity --lockfile-only"
        fingerprint = "#{flags}update <dependency_name> --depth Infinity --lockfile-only"
        [cmd, fingerprint]
      end

      sig { params(dependency_name: String, recursive: T::Boolean).returns(String) }
      def self.run_pnpm_deep_update_command(dependency_name, recursive: false)
        cmd, fingerprint = pnpm_deep_update_command(dependency_name, recursive: recursive)
        Helpers.run_pnpm_command(cmd, fingerprint: fingerprint)
      end

      sig { params(env: T.nilable(T::Hash[String, String])).returns(String) }
      def self.run_yarn_audit_fix_command(env: nil)
        # Fallback for transitive dependencies where `yarn up -R` is a no-op.
        # `yarn npm audit --fix` updates vulnerable deps in the lockfile. The
        # release-age gate env is threaded through so this lockfile-resolving
        # command honours the same cooldown (and security `=0` bypass) as the
        # primary add/dedupe/remove commands.
        Helpers.run_yarn_command(
          "npm audit --fix --mode update-lockfile",
          fingerprint: "npm audit --fix --mode update-lockfile",
          env: env
        )
      end
    end
  end
end
