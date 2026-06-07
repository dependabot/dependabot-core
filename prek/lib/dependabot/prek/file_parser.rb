# typed: strong
# frozen_string_literal: true

require "toml-rb"
require "sorbet-runtime"
require "dependabot/errors"
require "dependabot/file_parsers"
require "dependabot/pre_commit/file_parser"
require "dependabot/prek/package_manager"
require "dependabot/prek/version"
require "dependabot/prek/requirement"

module Dependabot
  module Prek
    # prek.toml is configuration-compatible with .pre-commit-config.yaml once
    # parsed, so we reuse PreCommit::FileParser's repo/hook handling and only
    # swap the file format (TOML) and the ecosystem name.
    class FileParser < Dependabot::PreCommit::FileParser
      extend T::Sig

      CONFIG_FILE_PATTERN = %r{(?:^|/)\.?prek\.toml$}i

      private

      sig { returns(String) }
      def package_manager_name
        "prek"
      end

      sig { returns(Regexp) }
      def config_file_pattern
        CONFIG_FILE_PATTERN
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(PackageManager.new, T.nilable(Dependabot::Prek::PackageManager))
      end

      sig { params(file: Dependabot::DependencyFile).returns(T.untyped) }
      def load_config(file)
        TomlRB.parse(T.must(file.content))
      rescue TomlRB::Error => e
        # TomlRB::Error covers both syntax errors (ParseError) and semantic
        # errors such as duplicate keys (ValueOverwriteError).
        raise Dependabot::DependencyFileNotParseable.new(file.path, e.message)
      end

      sig { override.void }
      def check_required_files
        return if dependency_files.any? { |f| f.name.match?(config_file_pattern) }

        raise "No prek configuration file found!"
      end

      # Extracts the trailing comment on a repo's `rev = "..."` line, e.g.
      # `rev = "<sha>"  # frozen: v4.4.0`. TOML comments are discarded by the
      # parser, so we scan the raw content like pre-commit does for YAML. The
      # `repo =` / `rev =` assignments are matched with a leading boundary so
      # both the `[[repos]]` table form and the inline-table array form
      # (`repos = [{ repo = "...", rev = "..." }]`) are handled.
      sig do
        override.params(
          file: Dependabot::DependencyFile,
          repo_url: String
        ).returns(T.nilable(String))
      end
      def rev_line_comment(file, repo_url)
        current_repo = T.let(nil, T.nilable(String))

        T.must(file.content).each_line do |line|
          repo_match = line.match(/(?:^|[\s{,])repo\s*=\s*["']([^"']+)["']/)
          current_repo = repo_match[1] if repo_match

          next unless current_repo == repo_url

          rev_match = line.match(/(?:^|[\s{,])rev\s*=\s*\S+.*?(#.*)$/)
          return T.must(rev_match[1]).rstrip if rev_match
        end

        nil
      end
    end
  end
end

Dependabot::FileParsers.register("prek", Dependabot::Prek::FileParser)
