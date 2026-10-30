# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module PreCommit
    # Locates repo entries in a prek.toml so their values can be read or
    # rewritten in place, keeping the file's formatting. Each `[[repos]]` table
    # and each inline table is its own scope, so keys may appear in any order
    # and several inline tables may share a line. String contents and comments
    # are blanked out before matching, so text inside them is never mistaken
    # for a key.
    module PrekToml
      extend T::Sig

      REPOS_TABLE_HEADER = /^[ \t]*\[\[[ \t]*repos[ \t]*\]\]/
      TABLE_HEADER = /^[ \t]*\[/
      STRING_VALUE = /\G(["'])(.*?)\1/
      # An unterminated string runs to the end of its line, so no input makes
      # the match backtrack.
      STRING_OR_COMMENT = /"(?:[^"\\\n]|\\.)*(?:"|$)|'[^'\n]*(?:'|$)|#[^\n]*/

      # Returns the character range of each `rev` value (inside its quotes)
      # in a repo entry whose `repo` is repo_url.
      sig { params(content: String, repo_url: String).returns(T::Array[T::Range[Integer]]) }
      def self.rev_value_ranges(content, repo_url)
        masked = mask(content)

        repo_scopes(masked).filter_map do |scope|
          repo = key_value_range(content, masked, scope, "repo")
          next unless repo && content[repo] == repo_url

          key_value_range(content, masked, scope, "rev")
        end
      end

      # Returns the trailing comment on the line holding offset, if any.
      sig { params(content: String, offset: Integer).returns(T.nilable(String)) }
      def self.line_comment(content, offset)
        line_end = content.index("\n", offset) || content.length
        comment_start = mask(content).index("#", offset)
        return unless comment_start && comment_start < line_end

        T.must(content[comment_start...line_end]).rstrip
      end

      sig { params(masked: String).returns(T::Array[T::Range[Integer]]) }
      def self.repo_scopes(masked)
        scopes = T.let([], T::Array[T::Range[Integer]])

        masked.scan(REPOS_TABLE_HEADER) do
          match = T.must(Regexp.last_match)
          scopes << (match.begin(0)...(masked.index(TABLE_HEADER, match.end(0)) || masked.length))
        end

        depth = 0
        start = 0
        masked.each_char.with_index do |char, index|
          if char == "{"
            start = index if depth.zero?
            depth += 1
          elsif char == "}"
            depth -= 1
            scopes << (start..index) if depth.zero?
          end
        end

        scopes
      end

      sig do
        params(content: String, masked: String, scope: T::Range[Integer], key: String)
          .returns(T.nilable(T::Range[Integer]))
      end
      def self.key_value_range(content, masked, scope, key)
        key_match = T.must(masked[scope]).match(/(?:^|[{,])[ \t]*#{key}[ \t]*=[ \t]*/)
        return unless key_match

        value_start = scope.begin + key_match.end(0)
        value_match = content.match(STRING_VALUE, value_start)
        return unless value_match

        (value_start + 1)...(value_start + 1 + T.must(value_match[2]).length)
      end

      # Replaces the contents of strings and comments with spaces, keeping the
      # opening quote or `#` and every offset intact.
      sig { params(content: String).returns(String) }
      def self.mask(content)
        content.gsub(STRING_OR_COMMENT) { |token| T.must(token[0]) + (" " * (token.length - 1)) }
      end
    end
  end
end
