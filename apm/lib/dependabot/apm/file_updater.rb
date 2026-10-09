# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Apm
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      MANIFEST_FILENAME = "apm.yml"
      LOCKFILE_FILENAME = "apm.lock.yaml"

      # What may follow a SHA pin on its line for `apm update`'s `# <tag>`
      # comment to be written: nothing but whitespace or an existing comment.
      LINE_REMAINDER_REGEX = /\A[ \t]*(?:#[^\r\n]*)?(?=\r?\n|\z)/

      require_relative "file_updater/lockfile_updater"

      # A single ref-bump edit, located by an absolute [start_offset, end_offset)
      # character range in the original manifest content.
      class Substitution < T::Struct
        const :start_offset, Integer
        const :end_offset, Integer
        const :text, String
      end

      sig { returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [/^apm\.yml$/, /^apm\.lock\.yaml$/]
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = manifest_files.filter_map do |file|
          next unless file_changed?(file)

          updated_file(file: file, content: updated_manifest_content(file))
        end

        updated_lockfile = updated_lockfile(updated_files)
        updated_files << updated_lockfile if updated_lockfile

        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      sig { override.void }
      def check_required_files
        return if get_original_file(MANIFEST_FILENAME)

        raise "No #{MANIFEST_FILENAME}!"
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def manifest_files
        dependency_files.select { |f| File.basename(f.name) == MANIFEST_FILENAME }
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def file_changed?(file)
        dependencies.any? { |dep| requirement_changed?(file, dep) }
      end

      # Regenerates the lockfile against the updated manifest. A branch pin
      # update changes only the lockfile, as the manifest still names the branch.
      # The lockfile is only ever updated, never created.
      sig do
        params(updated_manifests: T::Array[Dependabot::DependencyFile])
          .returns(T.nilable(Dependabot::DependencyFile))
      end
      def updated_lockfile(updated_manifests)
        lockfile = get_original_file(LOCKFILE_FILENAME)
        manifest = get_original_file(MANIFEST_FILENAME)
        return unless lockfile && manifest

        manifest_content = updated_manifests.find { |f| f.name == manifest.name }&.content || manifest.content
        content = LockfileUpdater.new(
          dependencies: dependencies,
          lockfile: lockfile,
          manifest_content: T.must(manifest_content),
          credentials: credentials,
          repo_contents_path: repo_contents_path
        ).updated_lockfile_content
        return if content == lockfile.content

        updated_file(file: lockfile, content: content)
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_manifest_content(file)
        original_content = T.must(file.content)
        content = apply_substitutions(original_content, substitutions_for(file, original_content))

        raise "Expected content to change!" if content == original_content

        content
      end

      # Collects every ref-bump substitution for `file`, each located by an
      # absolute range in the ORIGINAL content. Resolving all offsets against the
      # original (rather than mutating between edits) is what lets
      # `apply_substitutions` reorder them safely.
      sig { params(file: Dependabot::DependencyFile, content: String).returns(T::Array[Substitution]) }
      def substitutions_for(file, content)
        dependencies.flat_map do |dependency|
          previous_requirements = dependency.previous_requirements || []

          dependency.requirements.filter_map do |new_req|
            next unless new_req.file == file.name

            substitution_for(content, new_req, previous_requirements)
          end
        end
      end

      # Builds the substitution for a single requirement. The replacement rewrites
      # only the declaration substring inside the scalar's span slice, so any
      # surrounding quotes are preserved and an identical string elsewhere in the
      # file is never touched.
      sig do
        params(
          content: String,
          new_req: Dependabot::DependencyRequirement,
          previous_requirements: T::Array[Dependabot::DependencyRequirement]
        ).returns(T.nilable(Substitution))
      end
      def substitution_for(content, new_req, previous_requirements)
        declaration = new_req.metadata_string("declaration_string")
        new_ref = new_req.source_string("ref")
        return unless declaration && new_ref

        old_req = previous_requirements.find do |req|
          req.metadata_string("declaration_string") == declaration
        end
        old_ref = old_req&.source_string("ref")
        return unless old_ref && old_ref != new_ref

        # A quoted scalar may carry trailing whitespace after the ref (e.g.
        # `"owner/repo#v1.0.0 "`). PackageSpecifier strips it before parsing the
        # ref, but the stored declaration keeps it, so anchor the match before any
        # trailing whitespace and preserve that whitespace in the rewrite. An
        # end-anchored `##{old_ref}` check would otherwise miss and fail the whole
        # update with "Expected content to change!".
        ref_at_end = /##{Regexp.escape(old_ref)}(\s*)\z/
        return unless declaration.match?(ref_at_end)

        offsets = span_offsets(content, new_req.metadata_string("declaration_span"))
        return unless offsets

        start_offset, end_offset = offsets
        original = T.must(content[start_offset...end_offset])
        return unless original.include?(declaration)

        new_declaration = declaration.sub(ref_at_end, "##{new_ref}\\1")
        substitution = Substitution.new(
          start_offset: start_offset,
          end_offset: end_offset,
          text: original.sub(declaration, new_declaration)
        )
        with_release_tag_comment(content, substitution, new_req.metadata_string("release_tag"))
      end

      # Like `apm update`, annotates a bumped SHA pin with the release it now
      # points at, replacing any comment already on the line. The comment is
      # only written when nothing but whitespace or a comment follows the entry
      # on its line, so entries in a flow sequence are left uncommented.
      sig do
        params(content: String, substitution: Substitution, release_tag: T.nilable(String)).returns(Substitution)
      end
      def with_release_tag_comment(content, substitution, release_tag)
        return substitution unless release_tag

        line_remainder = content[substitution.end_offset..]&.match(LINE_REMAINDER_REGEX)
        return substitution unless line_remainder

        Substitution.new(
          start_offset: substitution.start_offset,
          end_offset: substitution.end_offset + line_remainder[0].to_s.length,
          text: "#{substitution.text} # #{release_tag}"
        )
      end

      # Applies the substitutions from the end of the file backwards. Rewriting in
      # descending start offset means a length change in one edit can never shift
      # the offsets of the edits still to be applied, so duplicate entries sharing
      # a line (e.g. a flow sequence) are all updated correctly.
      sig { params(content: String, substitutions: T::Array[Substitution]).returns(String) }
      def apply_substitutions(content, substitutions)
        substitutions.sort_by(&:start_offset).reverse.reduce(content) do |result, sub|
          "#{T.must(result[0...sub.start_offset])}#{sub.text}#{result[sub.end_offset..]}"
        end
      end

      # Resolves the encoded span to an absolute [start, end) character range in
      # `content`, or nil when the span is missing, malformed, or points past the
      # end of the current content.
      sig { params(content: String, declaration_span: T.nilable(String)).returns(T.nilable([Integer, Integer])) }
      def span_offsets(content, declaration_span)
        return unless declaration_span

        parts = declaration_span.split(":")
        return unless parts.length == 4

        lines = content.each_line.to_a
        start_offset = line_offset(lines, T.must(parts[0]).to_i) + T.must(parts[1]).to_i
        end_offset = line_offset(lines, T.must(parts[2]).to_i) + T.must(parts[3]).to_i
        return if start_offset >= end_offset || end_offset > content.length

        [start_offset, end_offset]
      end

      # Character offset of the start of the given 0-based line.
      sig { params(lines: T::Array[String], line: Integer).returns(Integer) }
      def line_offset(lines, line)
        lines.first(line).sum(&:length)
      end
    end
  end
end

Dependabot::FileUpdaters
  .register("apm", Dependabot::Apm::FileUpdater)
