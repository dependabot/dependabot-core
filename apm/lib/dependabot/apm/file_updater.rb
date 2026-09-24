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
        replace_declaration(content, declaration, new_declaration)
      end

      # Replaces a manifest entry with the bumped one, matching the declaration
      # only as a whole token so it never clips a longer entry that merely shares
      # the same prefix (e.g. `owner/repo` vs `owner/repo-two`).
      sig { params(content: String, old_declaration: String, new_declaration: String).returns(String) }
      def replace_declaration(content, old_declaration, new_declaration)
        boundary = %r{[\w./#-]}
        content.gsub(/(?<!#{boundary})#{Regexp.escape(old_declaration)}(?!#{boundary})/, new_declaration)
      end
    end
  end
end

Dependabot::FileUpdaters
  .register("apm", Dependabot::Apm::FileUpdater)
