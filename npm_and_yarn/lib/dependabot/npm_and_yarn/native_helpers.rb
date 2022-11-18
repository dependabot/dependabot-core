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

      def self.npm8_subdependency_update_command(dependency_names)
        # eventually this should be set based on the SharedHelper result
        dependency_type = "production"
        def dependency_type_to_flag(dependency_type)
          case dependency_type
          when "production"
            "--save"
          when "dev"
            "--save-dev"
          when "optional"
            "--save-optional"
          end
        end

        # NOTE: npm options
        # - `--force` ignores checks for platform (os, cpu) and engines
        # - `--dry-run=false` the updater sets a global .npmrc with dry-run: true to
        #   work around an issue in npm 6, we don't want that here
        # - `--ignore-scripts` disables prepare and prepack scripts which are run
        #   when installing git dependencies
        [
          "npm",
          "update",
          *dependency_names,
          "--force",
          "--dry-run",
          "false",
          "--ignore-scripts",
          "--package-lock-only",
          dependency_type_to_flag(dependency_type)
        ].join(" ")
      end
    end
  end
end
