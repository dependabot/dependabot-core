# typed: true
# frozen_string_literal: true

require "time"
require "open3"

require "dependabot/errors"
require "dependabot/shared_helpers"

module Dependabot
  module Python
    module Helpers
      def self.run_poetry_command(command, fingerprint: nil)
        start = Time.now
        command = SharedHelpers.escape_command(command)
        stdout, stderr, process = Open3.capture3(command)
        time_taken = Time.now - start

        # Raise an error with the output from the shell session if Poetry
        # returns a non-zero status
        return stdout if process.success?

        raise SharedHelpers::HelperSubprocessFailed.new(
          message: stderr,
          error_context: {
            command: command,
            fingerprint: fingerprint,
            time_taken: time_taken,
            process_exit_value: process.to_s
          }
        )
      end
    end
  end
end
