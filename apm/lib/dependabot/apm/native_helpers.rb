# typed: strict
# frozen_string_literal: true

require "pathname"
require "sorbet-runtime"

require "dependabot/shared_helpers"

module Dependabot
  module Apm
    module NativeHelpers
      extend T::Sig

      # APM renders its output through a terminal-width-aware console, which
      # wraps long error messages mid-sentence. A wide, colourless console keeps
      # each message on one line so errors can be matched reliably.
      COMMAND_ENV = T.let(
        {
          "COLUMNS" => "1000",
          "NO_COLOR" => "1",
          "GIT_TERMINAL_PROMPT" => "0"
        }.freeze,
        T::Hash[String, String]
      )

      sig { returns(String) }
      def self.apm_path
        clean_path(File.join(native_helpers_root, "apm/bin/apm"))
      end

      # Runs an APM CLI command (e.g. `lock`) in the current directory, raising
      # SharedHelpers::HelperSubprocessFailed with APM's output on failure.
      sig { params(command: String).returns(String) }
      def self.run_apm_command(command)
        SharedHelpers.run_shell_command(
          "#{apm_path} #{command}",
          env: COMMAND_ENV,
          fingerprint: "apm #{command}"
        )
      end

      sig { returns(String) }
      def self.native_helpers_root
        default_path = File.join(__dir__, "../../../helpers/install-dir")
        ENV.fetch("DEPENDABOT_NATIVE_HELPERS_PATH", default_path)
      end

      sig { params(path: String).returns(String) }
      def self.clean_path(path)
        Pathname.new(path).cleanpath.to_path
      end
    end
  end
end
