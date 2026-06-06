# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_updaters"
require "dependabot/pre_commit/file_updater"

module Dependabot
  module Prek
    # Reuses PreCommit::FileUpdater's dependency dispatch and only swaps the
    # ref-rewriting to match prek.toml's TOML syntax (`rev = "x"`) instead of
    # pre-commit's YAML syntax (`rev: x`).
    class FileUpdater < Dependabot::PreCommit::FileUpdater
      extend T::Sig

      # Matches a `repo = "..."` assignment anywhere a TOML key can begin: at the
      # start of a line (the `[[repos]]` table form) or after a `{`/`,`/space (the
      # inline-table array form). The leading boundary prevents matching the
      # `repos = [` array key.
      REPO_LINE_PATTERN = /(?:^|[\s{,])repo\s*=\s*["']([^"']+)["']/

      private

      # Tracks the current repo (handling both the multi-line `[[repos]]` table
      # form and the single-line inline-table form) and rewrites the matching
      # `rev = "..."` value.
      sig do
        params(
          content: String,
          repo_url: String,
          old_ref: String,
          new_ref: String,
          old_version: T.nilable(String),
          new_version: T.nilable(String)
        ).returns(String)
      end
      def replace_ref_in_content(content, repo_url, old_ref, new_ref, old_version: nil, new_version: nil)
        current_repo = T.let(nil, T.nilable(String))
        rev_pattern = rev_value_pattern(old_ref)

        updated_lines = content.lines.map do |line|
          repo_match = line.match(REPO_LINE_PATTERN)
          current_repo = repo_match[1] if repo_match

          next line unless current_repo == repo_url
          next line unless line.match?(rev_pattern)

          updated_line = line.sub(rev_pattern) do
            m = T.must(Regexp.last_match)
            "#{m[:lead]}#{m[:open]}#{new_ref}#{m[:close]}"
          end
          update_version_comment(updated_line, old_version, new_version)
        end

        updated_lines.join
      end

      # Builds a regex matching exactly the `rev = "<old_ref>"` value for the
      # given old_ref. The trailing lookahead anchors the value so an old_ref
      # that is a prefix of a longer on-file rev (e.g. "v4.4" vs "v4.4.0") does
      # not partially rewrite it.
      sig { params(old_ref: String).returns(Regexp) }
      def rev_value_pattern(old_ref)
        /
          (?<lead>(?:^|[\s{,])rev\s*=\s*)  # the rev key, with its preceding boundary
          (?<open>["']?)                   # optional opening quote
          #{Regexp.escape(old_ref)}        # the exact old ref
          (?<close>["']?)                  # optional closing quote
          (?=[\s,}\#]|$)                   # must terminate the value
        /x
      end
    end
  end
end

Dependabot::FileUpdaters
  .register("prek", Dependabot::Prek::FileUpdater)
