# frozen_string_literal: true

require "dependabot/shared_helpers"

module Dependabot
  module Bundler
    module NativeHelpers
      def self.run_bundler_subprocess(function:, args:, bundler_version:)
        SharedHelpers.run_helper_subprocess(
          command: helper_path(bundler_version: bundler_version),
          function: function,
          args: args,
          env: {
            # Bundler will pick the matching installed major version
            "BUNDLER_VERSION" => bundler_version,
            # Force bundler to use the helper Gemfile that has been bundled with
            # v1, otherwise it will point to core's bundler/Gemfile which will
            # be bundled with v2 once it's installed
            "BUNDLE_GEMFILE" => File.join(versioned_helper_path(bundler_version: bundler_version), "Gemfile"),
            # Unset ruby env set by running dependabot-core with bundle exec,
            # forcing bundler to reset them from helpers/v1
            "RUBYLIB" => nil,
            "RUBYOPT" => nil,
            "GEM_PATH" => nil,
            "GEM_HOME" => nil
          }
        )
      end

      def self.versioned_helper_path(bundler_version:)
        native_helper_version = "v#{bundler_version}"
        File.join(native_helpers_root, native_helper_version)
      end

      def self.helper_path(bundler_version:)
        "bundle exec ruby #{File.join(versioned_helper_path(bundler_version: bundler_version), 'run.rb')}"
      end

      def self.native_helpers_root
        helpers_root = ENV["DEPENDABOT_NATIVE_HELPERS_PATH"]
        return File.join(helpers_root, "bundler") unless helpers_root.nil?

        File.join(__dir__, "../../../helpers")
      end
    end
  end
end
