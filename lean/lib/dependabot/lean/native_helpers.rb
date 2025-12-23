# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/shared_helpers"

module Dependabot
  module Lean
    module NativeHelpers
      extend T::Sig

      sig do
        params(
          directory: String,
          credentials: T::Array[Dependabot::Credential]
        ).returns(T::Hash[String, T.untyped])
      end
      def self.run_lake_update(directory:, credentials:) # rubocop:disable Lint/UnusedMethodArgument
        run_helper(
          function: "update_all",
          args: { directory: directory }
        )
      end

      sig do
        params(
          directory: String,
          credentials: T::Array[Dependabot::Credential]
        ).returns(T::Hash[String, T.untyped])
      end
      def self.check_updates(directory:, credentials:) # rubocop:disable Lint/UnusedMethodArgument
        run_helper(
          function: "check_updates",
          args: { directory: directory }
        )
      end

      sig do
        params(
          directory: String
        ).returns(T::Hash[String, T.untyped])
      end
      def self.get_manifest(directory:)
        run_helper(
          function: "get_manifest",
          args: { directory: directory }
        )
      end

      class << self
        extend T::Sig

        private

        sig do
          params(
            function: String,
            args: T::Hash[Symbol, T.untyped]
          ).returns(T::Hash[String, T.untyped])
        end
        def run_helper(function:, args:)
          stdin_data = JSON.generate(
            {
              function: function,
              args: args
            }
          )

          stdout, stderr, status = Open3.capture3(
            helper_path,
            stdin_data: stdin_data
          )

          unless status.success?
            raise SharedHelpers::HelperSubprocessFailed.new(
              message: stderr,
              error_context: { function: function }
            )
          end

          JSON.parse(stdout)
        rescue JSON::ParserError => e
          raise SharedHelpers::HelperSubprocessFailed.new(
            message: "Invalid JSON response: #{e.message}",
            error_context: { function: function, stdout: stdout }
          )
        end

        sig { returns(String) }
        def helper_path
          native_helpers_root = ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", nil)

          if native_helpers_root
            File.join(native_helpers_root, "lean", "run.sh")
          else
            File.expand_path("../../helpers/run.sh", __dir__)
          end
        end
      end
    end
  end
end
