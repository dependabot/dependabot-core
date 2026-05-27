# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/shared_helpers"

module Dependabot
  module Deno
    module Helpers
      extend T::Sig

      # Wraps `deno <args>` via Dependabot's standard subprocess helper, so
      # failures surface as Dependabot::SharedHelpers::HelperSubprocessFailed
      # (consistent with cargo / bun / npm_and_yarn). DENO_DIR is scoped to
      # the working directory so concurrent jobs don't trample each other's
      # module cache.
      sig do
        params(
          args: String,
          dir: String
        ).returns(String)
      end
      def self.run_deno_command(*args, dir:)
        Dependabot::SharedHelpers.run_shell_command(
          "deno #{args.join(' ')}",
          cwd: dir,
          env: { "DENO_DIR" => File.join(dir, ".deno_cache") }
        )
      end
    end
  end
end
