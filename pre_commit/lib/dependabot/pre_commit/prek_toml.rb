# typed: strong
# frozen_string_literal: true

require "strscan"
require "sorbet-runtime"

module Dependabot
  module PreCommit
    # Locates values in a prek.toml so they can be read or rewritten in place,
    # keeping the file's formatting. Each `[[repos]]` table and each inline
    # table is its own scope, so keys may appear in any order and several
    # inline tables may share a line. String contents and comments are blanked
    # out before matching, so text inside them is never taken for TOML syntax.
    class PrekToml
      extend T::Sig

      REPOS_TABLE_HEADER = /^[ \t]*\[\[[ \t]*repos[ \t]*\]\]/
      HOOKS_TABLE_HEADER = /^[ \t]*\[\[[ \t]*repos[ \t]*\.[ \t]*hooks[ \t]*\]\]/
      TABLE_HEADER = /^[ \t]*\[/
      # Any table header except a `[repos.*]` sub-table, which still belongs to
      # the `[[repos]]` entry before it.
      NON_REPO_TABLE_HEADER = /^[ \t]*\[(?!\[?[ \t]*repos[ \t]*\.)/
      KEY = /(?:^|[{,])[ \t]*([A-Za-z0-9_-]+|"[^"\n]*"|'[^'\n]*')[ \t]*=[ \t]*/
      QUOTES = ['"', "'"].freeze

      # What follows each opening delimiter up to, then including, its closer.
      # Every pattern is matched anchored at the scanner position, so an
      # unterminated string or comment simply runs to the end of its line.
      TOKEN_BODIES = T.let(
        {
          '"""' => /(?:[^"\\]|\\.|"(?!""))*/m,
          "'''" => /(?:[^']|'(?!''))*/,
          '"' => /(?:[^"\\\n]|\\.)*/,
          "'" => /[^'\n]*/,
          "#" => /[^\n]*/
        }.freeze,
        T::Hash[String, Regexp]
      )
      TOKEN_CLOSERS = T.let(
        { '"""' => /"""/, "'''" => /'''/, '"' => /"/, "'" => /'/, "#" => // }.freeze,
        T::Hash[String, Regexp]
      )

      sig { params(content: String).void }
      def initialize(content)
        @content = content
        @masked = T.let(mask(content), String)
      end

      # Returns the range of each `rev` value (inside its quotes) in a repo
      # entry whose `repo` is repo_url.
      sig { params(repo_url: String).returns(T::Array[T::Range[Integer]]) }
      def rev_value_ranges(repo_url)
        repo_scopes(repo_url).filter_map { |scope| string_value(scope, "rev") }
      end

      # Returns the range of each additional_dependencies element (inside its
      # quotes) equal to dependency, in the hook hook_id of repo_url.
      sig do
        params(repo_url: String, hook_id: String, dependency: String)
          .returns(T::Array[T::Range[Integer]])
      end
      def additional_dependency_ranges(repo_url, hook_id, dependency)
        hooks = repo_scopes(repo_url).flat_map { |scope| hook_scopes(scope) }
        hooks.select { |hook| text(string_value(hook, "id")) == hook_id }
             .flat_map { |hook| array_strings(hook, "additional_dependencies") }
             .select { |range| @content[range] == dependency }
      end

      # Returns the trailing comment on the line holding offset, if any.
      sig { params(offset: Integer).returns(T.nilable(String)) }
      def line_comment(offset)
        line_end = @content.index("\n", offset) || @content.length
        comment_start = @masked.index("#", offset)
        return unless comment_start && comment_start < line_end

        T.must(@content[comment_start...line_end]).rstrip
      end

      private

      sig { params(repo_url: String).returns(T::Array[T::Range[Integer]]) }
      def repo_scopes(repo_url)
        scopes = header_tables(REPOS_TABLE_HEADER, NON_REPO_TABLE_HEADER) + inline_tables
        scopes.select { |scope| text(string_value(scope, "repo")) == repo_url }
      end

      sig { params(repo_scope: T::Range[Integer]).returns(T::Array[T::Range[Integer]]) }
      def hook_scopes(repo_scope)
        scopes = header_tables(HOOKS_TABLE_HEADER, TABLE_HEADER) + inline_tables
        scopes.select { |scope| scope != repo_scope && repo_scope.cover?(scope.begin) }
      end

      # Each table from a header matching header up to the next terminator.
      sig { params(header: Regexp, terminator: Regexp).returns(T::Array[T::Range[Integer]]) }
      def header_tables(header, terminator)
        tables = T.let([], T::Array[T::Range[Integer]])
        @masked.scan(header) do
          match = T.must(Regexp.last_match)
          tables << (match.begin(0)...(@masked.index(terminator, match.end(0)) || @masked.length))
        end
        tables
      end

      sig { returns(T::Array[T::Range[Integer]]) }
      def inline_tables
        @masked.each_char.with_index.filter_map do |char, index|
          next unless char == "{"

          closing = closing_index(index)
          index..closing if closing
        end
      end

      # The index of the bracket or brace closing the one at start.
      sig { params(start: Integer).returns(T.nilable(Integer)) }
      def closing_index(start)
        depth = 0
        (start...@masked.length).each do |index|
          case @masked[index]
          when "[", "{" then depth += 1
          when "]", "}"
            depth -= 1
            return index if depth.zero?
          end
        end
        nil
      end

      # The offset just past `key = ` in scope, for a bare or quoted key.
      sig { params(scope: T::Range[Integer], key: String).returns(T.nilable(Integer)) }
      def value_start(scope, key)
        T.must(@masked[scope]).scan(KEY) do
          match = T.must(Regexp.last_match)
          name = T.must(@content[(scope.begin + match.begin(1))...(scope.begin + match.end(1))])
          name = T.must(name[1...-1]) if QUOTES.include?(name[0])
          return scope.begin + match.end(0) if name == key
        end
        nil
      end

      # The range inside the quotes of the string assigned to key in scope.
      sig { params(scope: T::Range[Integer], key: String).returns(T.nilable(T::Range[Integer])) }
      def string_value(scope, key)
        start = value_start(scope, key)
        return unless start

        quote = @masked[start]
        return unless QUOTES.include?(quote)

        closing = @masked.index(T.must(quote), start + 1)
        (start + 1)...closing if closing
      end

      # The ranges inside the quotes of each string in the array assigned to
      # key in scope.
      sig { params(scope: T::Range[Integer], key: String).returns(T::Array[T::Range[Integer]]) }
      def array_strings(scope, key)
        start = value_start(scope, key)
        return [] unless start && @masked[start] == "["

        closing = closing_index(start)
        return [] unless closing

        quotes = (start..closing).select { |index| QUOTES.include?(@masked[index]) }
        quotes.each_slice(2).filter_map { |open, close| (T.must(open) + 1)...close if close }
      end

      sig { params(range: T.nilable(T::Range[Integer])).returns(T.nilable(String)) }
      def text(range)
        @content[range] if range
      end

      # Replaces string contents and comments with spaces, keeping their
      # delimiters, newlines and every offset intact.
      sig { params(content: String).returns(String) }
      def mask(content)
        scanner = StringScanner.new(content)
        masked = +""
        masked << (scanner.scan(/[^"'#]+/) || masked_token(scanner)) until scanner.eos?
        masked
      end

      sig { params(scanner: StringScanner).returns(String) }
      def masked_token(scanner)
        opener = T.must(scanner.scan(/"""|'''|["'#]/))
        body = scanner.scan(T.must(TOKEN_BODIES[opener])).to_s
        closer = scanner.scan(T.must(TOKEN_CLOSERS[opener])).to_s
        opener + body.gsub(/[^\n]/, " ") + closer
      end
    end
  end
end
