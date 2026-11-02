# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

require "dependabot/nimble/manifest"

module Dependabot
  module Nimble
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = manifests.filter_map do |file|
          content = updated_content(file)
          next if content == file.content

          updated_file(file: file, content: content)
        end

        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def manifests
        dependency_files.select { |file| file.name.end_with?(FileFetcher::MANIFEST_SUFFIX) }
      end

      # Edits the version of each `requires` string in place, last to first so earlier offsets hold.
      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def updated_content(file)
        content = file.content.to_s.dup
        entries = Manifest.new(content).dependencies
        replacements = entries.map.with_index { |entry, index| [entry, new_requirement(file, entry, entries, index)] }

        replacements.reverse_each do |entry, requirement|
          next if requirement.nil? || requirement == entry.requirement

          content[entry.requirement_start...entry.requirement_end] = requirement
        end
        content
      end

      # The requirement a dependency now has for the nth time the file mentions it.
      sig do
        params(
          file: Dependabot::DependencyFile,
          entry: Manifest::Requires,
          entries: T::Array[Manifest::Requires],
          index: Integer
        ).returns(T.nilable(String))
      end
      def new_requirement(file, entry, entries, index)
        dependency = dependencies.find { |candidate| candidate.name == entry.name }
        return unless dependency

        occurrence = entries.first(index).count { |earlier| earlier.name == entry.name }
        dependency.requirements
                  .select { |requirement| requirement.file == file.name }[occurrence]
                  &.requirement_string
      end

      sig { override.void }
      def check_required_files
        return if manifests.any?

        raise Dependabot::DependencyFileNotFound.new(nil, FileFetcher.required_files_message)
      end
    end
  end
end

Dependabot::FileUpdaters.register("nimble", Dependabot::Nimble::FileUpdater)
