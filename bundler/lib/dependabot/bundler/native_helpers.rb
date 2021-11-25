# frozen_string_literal: true

require "bundler"
require "dependabot/shared_helpers"

module Dependabot
  module Bundler
    module NativeHelpers
      class BundleCommand
        MAX_SECONDS = 1800
        MIN_SECONDS = 60

        def initialize(timeout_seconds)
          @timeout_seconds = clamp(timeout_seconds)
        end

        def build(script)
          [timeout_command, :bundle, :exec, :ruby, script].compact.join(" ")
        end

        private

        attr_reader :timeout_seconds

        def timeout_command
          "timeout -s HUP #{timeout_seconds}" unless timeout_seconds.zero?
        end

        def clamp(seconds)
          # Tweak this value to tune the default timeout in seconds
          return 60 unless seconds

          seconds.to_i.clamp(MIN_SECONDS, MAX_SECONDS)
        end
      end

      def self.run_bundler_subprocess(function:, args:, bundler_version:, options: {})
        # Run helper suprocess with all bundler-related ENV variables removed
        bundler_major_version = bundler_version.split(".").first
        helpers_path = versioned_helper_path(bundler_version: bundler_major_version)
        ::Bundler.with_original_env do
          command = BundleCommand.
                    new(options[:timeout_per_operation_seconds]).
                    build(File.join(helpers_path, "run.rb"))
          SharedHelpers.run_helper_subprocess(
            command: command,
            function: function,
            args: args,
            env: {
              # Bundler will pick the matching installed major version
              "BUNDLER_VERSION" => bundler_version,
              "BUNDLE_GEMFILE" => File.join(helpers_path, "Gemfile"),
              # Prevent the GEM_HOME from being set to a folder owned by root
              "GEM_HOME" => File.join(helpers_path, ".bundle")
            }
          )
        rescue SharedHelpers::HelperSubprocessFailed => e
          # TODO: Remove once we stop stubbing out the V2 native helper
          raise Dependabot::NotImplemented, e.message if e.error_class == "Functions::NotImplementedError"

          raise
        end
      end

      def self.versioned_helper_path(bundler_version:)
        File.join(native_helpers_root, "v#{bundler_version}")
      end

      def self.native_helpers_root
        helpers_root = ENV["DEPENDABOT_NATIVE_HELPERS_PATH"]
        return File.join(helpers_root, "bundler") unless helpers_root.nil?

        File.join(__dir__, "../../../helpers")
      end
    end
  end
end
