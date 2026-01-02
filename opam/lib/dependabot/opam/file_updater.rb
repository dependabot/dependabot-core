# typed: strict
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Opam
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      require_relative "file_updater/opam_file_updater"

      sig { returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [/\.opam$/, /^opam$/]
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def updated_dependency_files
        updated_files = []

        opam_files.each do |file|
          next unless file_changed?(file)

          updated_files << updated_file(
            file: file,
            content: updated_opam_file_content(file)
          )
        end

        updated_files
      end

      private

      sig { returns(T::Array[DependencyFile]) }
      def opam_files
        dependency_files.select { |f| f.name.end_with?(".opam") || f.name == "opam" }
      end

      sig { params(file: DependencyFile).returns(String) }
      def updated_opam_file_content(file)
        content = T.must(file.content).dup

        dependencies.each do |dependency|
          content = OpamFileUpdater.update_dependency_version(
            content: content,
            dependency: dependency
          )
        end

        content
      end

      sig { override.returns(T::Boolean) }
      def check_required_files # rubocop:disable Naming/PredicateMethod
        opam_files.any?
      end
    end
  end
end

Dependabot::FileUpdaters
  .register("opam", Dependabot::Opam::FileUpdater)
