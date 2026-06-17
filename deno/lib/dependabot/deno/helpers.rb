# typed: strict
# frozen_string_literal: true

require "json"
require "pathname"
require "sorbet-runtime"

require "dependabot/shared_helpers"

module Dependabot
  module Deno
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

      sig { params(content: T.nilable(String)).returns(T::Hash[String, T.untyped]) }
      def self.parse_json_or_jsonc(content)
        return {} unless content

        cleaned = content.gsub(JSONC_TOKEN) { ::Regexp.last_match(1) || "" }

        parsed = JSON.parse(cleaned)
        # A deno.json(c) must be a JSON object. Guard here so a malformed manifest
        # (e.g. a top-level array) surfaces as a clear parse error rather than an
        # opaque sorbet-runtime type error at the call site.
        raise JSON::ParserError, "Expected a JSON object, got #{parsed.class}" unless parsed.is_a?(Hash)

        parsed
      end

      # True when `path` is a repo-relative path with no traversal. Workspace
      # member paths are derived from manifest content, so absolute paths
      # ("/etc") or ".." segments must never be used as fetch/write targets —
      # File.join would otherwise escape the repo checkout or temp directory.
      sig { params(path: String).returns(T::Boolean) }
      def self.safe_relative_path?(path)
        return false if path.empty?
        return false if Pathname.new(path).absolute?

        Pathname.new(path).each_filename.none?("..")
      end

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
