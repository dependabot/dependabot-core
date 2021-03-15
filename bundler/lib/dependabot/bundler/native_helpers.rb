# frozen_string_literal: true

require "bundler"
require "dependabot/shared_helpers"

module Dependabot
  module Bundler
    module NativeHelpers
      def self.run_bundler_subprocess(function:, args:, bundler_version:)
        # Run helper suprocess with all bundler-related ENV variables removed
        ::Bundler.with_original_env do
          SharedHelpers.run_helper_subprocess(
            command: helper_path(bundler_version: bundler_version),
            function: function,
            args: args,
            env: {
              # Bundler will pick the matching installed major version
              "BUNDLER_VERSION" => bundler_version,
              "BUNDLE_GEMFILE" => File.join(versioned_helper_path(bundler_version: bundler_version), "Gemfile"),
              "BUNDLE_PATH" => File.join(versioned_helper_path(bundler_version: bundler_version), ".bundle")
            }
          )
        rescue SharedHelpers::HelperSubprocessFailed => e
          # TODO: Remove once we stop stubbing out the V2 native helper
          if e.error_class == "Functions::NotImplementedError"
            raise Dependabot::NotImplemented, e.message
          end

          raise
        end
      end

      def self.versioned_helper_path(bundler_version:)
        native_helper_version = "v#{bundler_version}"
        File.join(native_helpers_root, native_helper_version)
      end

      def self.helper_path(bundler_version:)
        "ruby #{File.join(versioned_helper_path(bundler_version: bundler_version), 'run.rb')}"
      end

      def self.native_helpers_root
        helpers_root = ENV["DEPENDABOT_NATIVE_HELPERS_PATH"]
        return File.join(helpers_root, "bundler") unless helpers_root.nil?

        File.join(__dir__, "../../../helpers")
      end
    end
  end
end
