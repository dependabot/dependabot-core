# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module PreCommit
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        dependency_files.each do |file|
          next unless requirement_changed?(file, dependency)

          updated_files <<
            updated_file(
              file: file,
              content: updated_config_file_content(file)
            )
        end

        updated_files.reject! { |f| dependency_files.include?(T.cast(f, Dependabot::DependencyFile)) }
        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      sig { returns(Dependabot::Dependency) }
      def dependency
        T.must(dependencies.first)
      end

      sig { override.void }
      def check_required_files
        return if dependency_files.any?

        raise "No pre-commit config files!"
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_config_file_content(file)
        updated_requirement_pairs = requirement_pairs_for_file(file)
        updated_content = T.must(file.content)

        updated_requirement_pairs.each do |new_req, old_req|
          updated_content = apply_requirement_update(updated_content, new_req, old_req, file)
        end

        updated_content
      end

      sig do
        params(file: Dependabot::DependencyFile)
          .returns(T::Array[[T::Hash[Symbol, T.untyped], T::Hash[Symbol, T.untyped]]])
      end
      def requirement_pairs_for_file(file)
        pairs = dependency.requirements.zip(T.must(dependency.previous_requirements))
        filtered_pairs = pairs.reject do |new_req, old_req|
          next true unless old_req

          file_name = T.cast(new_req[:file], T.nilable(String))
          next true if file_name != file.name

          new_source = T.cast(new_req[:source], T.nilable(T::Hash[Symbol, T.untyped]))
          old_source = T.cast(old_req[:source], T.nilable(T::Hash[Symbol, T.untyped]))
          new_source == old_source
        end

        filtered_pairs.map { |new_req, old_req| [new_req, T.must(old_req)] }
      end

      sig do
        params(
          content: String,
          new_req: T::Hash[Symbol, T.untyped],
          old_req: T::Hash[Symbol, T.untyped],
          file: Dependabot::DependencyFile
        ).returns(String)
      end
      def apply_requirement_update(content, new_req, old_req, file)
        new_source = T.cast(new_req.fetch(:source), T::Hash[Symbol, T.untyped])
        source_type = T.cast(new_source.fetch(:type), String)

        case source_type
        when "git"
          apply_git_requirement_update(content, new_req, old_req, file)
        when "additional_dependency"
          apply_additional_dependency_update(content, new_req, old_req)
        else
          content
        end
      end

      sig do
        params(
          content: String,
          new_req: T::Hash[Symbol, T.untyped],
          old_req: T::Hash[Symbol, T.untyped],
          file: Dependabot::DependencyFile
        ).returns(String)
      end
      def apply_git_requirement_update(content, new_req, old_req, file)
        new_source = T.cast(new_req.fetch(:source), T::Hash[Symbol, T.untyped])
        old_source = T.cast(old_req.fetch(:source), T::Hash[Symbol, T.untyped])
        repo_url = T.cast(old_source.fetch(:url), String)
        old_ref = T.cast(old_source.fetch(:ref), String)
        new_ref = T.cast(new_source.fetch(:ref), String)

        new_metadata = T.cast(new_req.fetch(:metadata, {}), T::Hash[Symbol, T.untyped])
        old_version = T.cast(new_metadata[:comment_version], T.nilable(String))
        new_version = T.cast(new_metadata[:new_comment_version], T.nilable(String))

        replace_ref_in_content(
          content,
          repo_url,
          old_ref,
          new_ref,
          file,
          old_version: old_version,
          new_version: new_version
        )
      end

      sig do
        params(
          content: String,
          new_req: T::Hash[Symbol, T.untyped],
          old_req: T::Hash[Symbol, T.untyped]
        ).returns(String)
      end
      def apply_additional_dependency_update(content, new_req, old_req)
        old_source = T.cast(old_req.fetch(:source), T::Hash[Symbol, T.untyped])
        new_source = T.cast(new_req.fetch(:source), T::Hash[Symbol, T.untyped])

        old_string = T.cast(old_source.fetch(:original_string), String)
        new_string = T.cast(new_source.fetch(:original_string), String)

        replace_additional_dependency_in_content(content, old_string, new_string)
      end

      # Any .toml dependency file is rewritten as TOML; everything else as YAML.
      # In practice only prek.toml / .prek.toml reach here (the fetcher gates on
      # CONFIG_FILE_PATTERN), which is the sole TOML config pre-commit supports.
      sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def toml?(file)
        file.name.end_with?(".toml")
      end

      sig do
        params(
          content: String,
          repo_url: String,
          old_ref: String,
          new_ref: String,
          file: Dependabot::DependencyFile,
          old_version: T.nilable(String),
          new_version: T.nilable(String)
        ).returns(String)
      end
      def replace_ref_in_content(content, repo_url, old_ref, new_ref, file, old_version: nil, new_version: nil)
        if toml?(file)
          replace_ref_in_toml(content, repo_url, old_ref, new_ref, old_version: old_version, new_version: new_version)
        else
          replace_ref_in_yaml(content, repo_url, old_ref, new_ref, old_version: old_version, new_version: new_version)
        end
      end

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
      def replace_ref_in_yaml(content, repo_url, old_ref, new_ref, old_version: nil, new_version: nil)
        current_repo = T.let(nil, T.nilable(String))

        updated_lines = content.lines.map do |line|
          repo_match = line.match(/^\s*-\s*repo:\s*["']?([^"'\s]+)["']?/)
          current_repo = repo_match[1] if repo_match

          if current_repo == repo_url &&
             line.match?(/^\s*rev:\s+["']?#{Regexp.escape(old_ref)}["']?(\s*(?:#.*)?)?$/)
            updated_line = line.sub(/(["']?)#{Regexp.escape(old_ref)}(["']?)/, "\\1#{new_ref}\\2")
            updated_line = update_version_comment(updated_line, old_version, new_version)
            updated_line
          else
            line
          end
        end

        updated_lines.join
      end

      # Matches a `repo = "..."` assignment anywhere a TOML key can begin: at the
      # start of a line (the `[[repos]]` table form) or after a `{`/`,`/space (the
      # inline-table array form). The leading boundary prevents matching the
      # `repos = [` array key.
      REPO_LINE_PATTERN = /(?:^|[\s{,])repo\s*=\s*["']([^"']+)["']/

      # A `[[repos]]` array-of-tables header. Used to reset the current-repo
      # scope so a stray `rev =` before this table's `repo =` is not attributed
      # to the previous table.
      REPOS_TABLE_HEADER = /^\s*\[\[\s*repos\s*\]\]/

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
      def replace_ref_in_toml(content, repo_url, old_ref, new_ref, old_version: nil, new_version: nil)
        current_repo = T.let(nil, T.nilable(String))
        rev_pattern = rev_value_pattern(old_ref)

        updated_lines = content.lines.map do |line|
          current_repo = nil if line.match?(REPOS_TABLE_HEADER)

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

      sig do
        params(
          line: String,
          old_version: T.nilable(String),
          new_version: T.nilable(String)
        ).returns(String)
      end
      def update_version_comment(line, old_version, new_version)
        return line unless old_version && new_version

        pattern = /
          (                # 1: comment prefix
            \#\s*          # '#' and optional whitespace
            (?:frozen:\s*)? # optional 'frozen:' label
          )
          #{Regexp.escape(old_version)} # the old version
          (.*)$            # 2: trailing content (whitespace or other characters) up to end of line
        /x

        line.sub(pattern, "\\1#{new_version}\\2")
      end

      sig do
        params(content: String, old_string: String, new_string: String).returns(String)
      end
      def replace_additional_dependency_in_content(content, old_string, new_string)
        # Use line-by-line replacement to avoid variable-length look-behind issues
        # We look for the exact dependency string in various YAML formats
        escaped_old = Regexp.escape(old_string)

        updated_lines = content.lines.map do |line|
          # Check if this line contains the dependency in additional_dependencies context
          # Matches formats like:
          # - types-requests==1.0.0
          # - 'types-requests==1.0.0'
          # - "types-requests==1.0.0"
          # [..., types-requests==1.0.0, ...]
          if line.match?(/^\s*-\s*['"]?#{escaped_old}['"]?\s*$/) || # Block style
             line.match?(/[\[,]\s*['"]?#{escaped_old}['"]?\s*[,\]]/) || # Flow style
             line.match?(/^\s*-\s*['"]?#{escaped_old}['"]?\s*#/) # With comment
            line.gsub(old_string, new_string)
          else
            line
          end
        end

        updated_lines.join
      end
    end
  end
end

Dependabot::FileUpdaters
  .register("pre_commit", Dependabot::PreCommit::FileUpdater)
