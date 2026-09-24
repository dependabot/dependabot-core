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

      sig { returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [/^apm\.yml$/]
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = manifest_files.filter_map do |file|
          next unless file_changed?(file)

          updated_file(file: file, content: updated_manifest_content(file))
        end

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
        dependency_files.select { |f| f.name.end_with?(MANIFEST_FILENAME) && !f.name.end_with?(LOCKFILE_FILENAME) }
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def file_changed?(file)
        dependencies.any? { |dep| requirement_changed?(file, dep) }
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_manifest_content(file)
        content = T.must(file.content)

        dependencies.each do |dep|
          content = update_declarations_for(content, dep, file)
        end

        raise "Expected content to change!" if content == file.content

        content
      end

      sig do
        params(
          content: String,
          dependency: Dependabot::Dependency,
          file: Dependabot::DependencyFile
        ).returns(String)
      end
      def update_declarations_for(content, dependency, file)
        previous_requirements = dependency.previous_requirements || []

        dependency.requirements.each do |new_req|
          next unless new_req.file == file.name

          content = apply_ref_bump(content, new_req, previous_requirements)
        end

        content
      end

      sig do
        params(
          content: String,
          new_req: Dependabot::DependencyRequirement,
          previous_requirements: T::Array[Dependabot::DependencyRequirement]
        ).returns(String)
      end
      def apply_ref_bump(content, new_req, previous_requirements)
        declaration = new_req.metadata_string("declaration_string")
        new_ref = new_req.source_string("ref")
        return content unless declaration && new_ref

        old_req = previous_requirements.find do |req|
          req.metadata_string("declaration_string") == declaration
        end
        old_ref = old_req&.source_string("ref")
        return content unless old_ref && old_ref != new_ref
        return content unless declaration.end_with?("##{old_ref}")

        new_declaration = declaration.sub(/#{Regexp.escape("##{old_ref}")}\z/, "##{new_ref}")
        declaration_span = new_req.metadata_string("declaration_span")
        replace_declaration(content, declaration, new_declaration, declaration_span)
      end

      # Rewrites the entry at its exact source span (recorded from the YAML AST
      # at parse time as "start_line:start_column:end_line:end_column", 0-based).
      # Operating on the precise scalar range supports both block and flow
      # sequences, preserves any surrounding quotes, and never rewrites an
      # identical string elsewhere in the file (a comment, a `notes:` value, or
      # a different dependency block).
      sig do
        params(
          content: String,
          old_declaration: String,
          new_declaration: String,
          declaration_span: T.nilable(String)
        ).returns(String)
      end
      def replace_declaration(content, old_declaration, new_declaration, declaration_span)
        offsets = span_offsets(content, declaration_span)
        return content unless offsets

        start_offset, end_offset = offsets
        original = T.must(content[start_offset...end_offset])
        return content unless original.include?(old_declaration)

        updated = original.sub(old_declaration, new_declaration)
        "#{T.must(content[0...start_offset])}#{updated}#{content[end_offset..]}"
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
