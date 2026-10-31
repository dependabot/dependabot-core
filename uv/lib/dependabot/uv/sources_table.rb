# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/python/file_parser/pyproject_document"

module Dependabot
  module Uv
    # Where [tool.uv.sources] sits in a manifest's text. The parser decides which entries can be
    # rewritten and the file updater rewrites them, so both have to agree on the table's extent: over
    # the whole file a line of the same shape in another tool's table answers for either.
    module SourcesTable
      extend T::Sig

      # A trailing comment and a CRLF line ending both belong on this line, and neither should turn
      # the feature off without a word.
      HEADER = /^[ \t]*\[tool\.uv\.sources\][ \t]*(?:\#[^\r\n]*)?\r?$/
      NEXT_TABLE = /^[ \t]*\[/

      # What the rewrite anchors on: the key verbatim at the start of its line, and the tag it is
      # expected to carry. Both sides use this, so what the parser accepts is exactly what can be
      # rewritten - a shape only one of them understood is what turned a silent no-op into a job
      # failure.
      sig { params(key: String, ref: String).returns(Regexp) }
      def self.tag_regex(key, ref)
        # Quoting is the only legal TOML spelling for a name carrying a dot - zope.interface,
        # ruamel.yaml - so both the key and the inner `tag` are matched with or without quotes. The
        # `,` before `tag` is what stops the pattern latching onto the tail of another key.
        /
          (^[ \t]*["']?#{Regexp.escape(key)}["']?[ \t]*=[ \t]*
           \{(?:[^}]*?,)?[ \t]*["']?tag["']?[ \t]*=[ \t]*["'])
          #{Regexp.escape(ref)}
          (["'])
        /x
      end

      # The git-and-tag entries of a manifest that this file can rewrite, keyed as the author wrote
      # them. TomlRB is stricter than the tomli the Python helper uses, and this is the first time the
      # Ruby side reads a workspace member manifest, so one it rejects yields nothing rather than
      # failing the job.
      sig { params(file: Dependabot::DependencyFile).returns(T::Hash[String, T::Hash[Symbol, String]]) }
      def self.writable_for(file)
        document = Dependabot::Python::FileParser::PyprojectDocument.from_file(file)
        writable(T.must(file.content), document.uv_git_tag_sources)
      rescue Dependabot::DependencyFileNotParseable
        {}
      end

      # The entries of `sources` this file can rewrite. Reporting a moved ref for one it cannot reach
      # would fail the job, where before the pin was never updated.
      sig do
        params(content: String, sources: T::Hash[String, T::Hash[Symbol, String]])
          .returns(T::Hash[String, T::Hash[Symbol, String]])
      end
      def self.writable(content, sources)
        found = span(content)
        return {} unless found

        table = found[1]
        sources.select { |key, source| table.match?(tag_regex(key, T.must(source[:ref]))) }
      end

      # The table's own text, and the range it occupies in the manifest.
      sig { params(content: String).returns(T.nilable([T::Range[Integer], String])) }
      def self.span(content)
        header = content.match(HEADER)
        return nil unless header

        from = header.end(0)
        rest = content[from..] || ""
        nxt = rest.match(NEXT_TABLE)
        to = nxt ? from + nxt.begin(0) : content.length
        [Range.new(from, to, true), T.must(content[from...to])]
      end
    end
  end
end
