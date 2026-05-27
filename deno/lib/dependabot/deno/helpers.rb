# typed: strict
# frozen_string_literal: true

require "open3"
require "sorbet-runtime"

module Dependabot
  module Deno
    module Helpers
      extend T::Sig

      class DenoCommandError < StandardError; end

      # Cap subprocess output bubbled into error messages so they stay readable
      # in dependabot-core's error reporting (and any user-visible PR comments
      # downstream).
      MAX_ERROR_OUTPUT_BYTES = T.let(2_000, Integer)

      sig do
        params(
          args: String,
          dir: String
        ).returns(String)
      end
      def self.run_deno_command(*args, dir:)
        env = { "DENO_DIR" => File.join(dir, ".deno_cache") }
        output, status = Open3.capture2e(env, "deno", *args, chdir: dir)

        unless status.success?
          raise DenoCommandError,
                "deno #{args.join(' ')} failed (exit #{status.exitstatus}): #{truncate(output)}"
        end

        output
      end

      sig { params(output: String).returns(String) }
      def self.truncate(output)
        return output if output.bytesize <= MAX_ERROR_OUTPUT_BYTES

        head_bytes = MAX_ERROR_OUTPUT_BYTES / 2
        head = output.byteslice(0, head_bytes)
        tail = output.byteslice(-head_bytes, head_bytes)
        omitted = output.bytesize - (2 * head_bytes)
        "#{head}\n... [#{omitted} bytes omitted] ...\n#{tail}"
      end
      private_class_method :truncate
    end
  end
end
