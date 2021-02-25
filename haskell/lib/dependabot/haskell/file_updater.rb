# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/errors"

module Dependabot
  module Haskell
    class FileUpdater < Dependabot::FileUpdaters::Base
      def self.updated_files_regex
        [%r{.+\.cabal$}]
      end

      def updated_dependency_files
        updated_files = []

        dependency_files.each do |file|
          next unless requirement_changed?(file, dependency)

          updated_files <<
            updated_file(
              file: file,
              content: updated_cabal_file_content(file)
            )
        end

        updated_files.reject! { |f| dependency_files.include?(f) }
        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      def dependency
        # For now, we'll only ever be updating a single dependency
        dependencies.first
      end

      def updated_cabal_file_content(file)
        updated_requirement_pairs =
          dependency.requirements.zip(dependency.previous_requirements).
          reject do |new_req, old_req|
            next true if new_req[:file] != file.name

            new_req[:source] == old_req[:source]
          end

        updated_content = file.content

        old_declaration = updated_requirement_pairs.
            first[1].fetch(:metadata).fetch(:declaration_string)
        new_declaration = old_declaration
        updated_requirement_pairs.each do |new_req, old_req|
          new_declaration = new_declaration.
              gsub(old_req[:requirement], new_req[:requirement])
        end
        updated_content = updated_content.
            gsub(old_declaration, new_declaration)
        updated_content
      end

      def check_required_files
        file_names = dependency_files.map(&:name)

        return if file_names.any? { |name| name.match?(%r{.+\.cabal$}) }

        raise "A cabal file must be provided!"
      end

    end
  end
end

Dependabot::FileUpdaters.
  register("haskell", Dependabot::Haskell::FileUpdater)
