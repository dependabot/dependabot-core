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
          unsetenv_others: true,
          env: {
            # Bundler will pick the matching installed major version
            "BUNDLER_VERSION" => bundler_version,
            # Required to find the ruby bin
            "PATH" => ENV["PATH"],
            # # Requried to create tmp directories in a writeable folder
            "HOME" => ENV["HOME"],
            # Required to git clone to a writeable folder
            "GEM_HOME" => ENV["GEM_HOME"],
            # Required by git fetch
            "SSH_AUTH_SOCK" => ENV["SSH_AUTH_SOCK"],
            # Env set by the runner
            "SSL_CERT_FILE" => ENV["SSL_CERT_FILE"],
            "http_proxy" => ENV["http_proxy"],
            "HTTP_PROXY" => ENV["HTTP_PROXY"],
            "https_proxy" => ENV["https_proxy"],
            "HTTPS_PROXY" => ENV["HTTPS_PROXY"]
          }
        )
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
