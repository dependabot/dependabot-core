# typed: strict
# frozen_string_literal: true

require "open3"
require "sorbet-runtime"

module Dependabot
  module Deno
    module Helpers
      extend T::Sig

      class DenoCommandError < StandardError; end

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
          raise DenoCommandError, "deno #{args.join(' ')} failed (exit #{status.exitstatus}): #{output}"
        end

        output
      end
    end
  end
end
