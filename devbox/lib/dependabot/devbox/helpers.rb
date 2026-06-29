# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/shared_helpers"

module Dependabot
  module Devbox
    module Helpers
      extend T::Sig

      # Matches either a JSON string literal (with escapes), a line comment, a
      # block comment, or a trailing comma. The alternation lets gsub preserve
      # strings while stripping the JSONC-only constructs, so e.g. "//" inside a
      # URL value is not mistaken for the start of a comment.
      JSONC_TOKEN = T.let(
        %r{
          ("(?:\\.|[^"\\])*")    # JSON string literal
          | //[^\n]*             # line comment
          | /\*.*?\*/            # block comment
          | ,(?=\s*[\}\]])       # trailing comma
        }mx,
        Regexp
      )

      sig { params(content: T.nilable(String)).returns(Hash) }
      def self.parse_json_or_jsonc(content)
        return {} unless content

        cleaned = content.gsub(JSONC_TOKEN) { ::Regexp.last_match(1) || "" }

        parsed = JSON.parse(cleaned)
        # A devbox.json must be a JSON object. Guard here so a malformed manifest
        # (e.g. a top-level array) surfaces as a clear parse error rather than an
        # opaque sorbet-runtime type error at the call site.
        raise JSON::ParserError, "Expected a JSON object, got #{parsed.class}" unless parsed.is_a?(Hash)

        parsed
      end

      # Wraps `devbox <args>` via Dependabot's standard subprocess helper, so
      # failures surface as Dependabot::SharedHelpers::HelperSubprocessFailed
      # (consistent with cargo / bun / npm_and_yarn). The Devbox/Nix caches are
      # scoped to the working directory so concurrent jobs don't trample each
      # other's state.
      sig do
        params(
          args: String,
          dir: String
        ).returns(String)
      end
      def self.run_devbox_command(*args, dir:)
        Dependabot::SharedHelpers.run_shell_command(
          "devbox #{args.join(' ')}",
          cwd: dir,
          env: {
            "DEVBOX_CACHE" => File.join(dir, ".devbox_cache"),
            "XDG_CACHE_HOME" => File.join(dir, ".cache"),
            "HOME" => dir
          }
        )
      end
    end
  end
end
