# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/error_report_context"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Elm
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/elm_json_updater"

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = T.let([], T::Array[Dependabot::DependencyFile])

        elm_json_files.each do |file|
          next unless file_changed?(file)

          updated_files <<
            updated_file(
              file: file,
              content: T.must(updated_elm_json_content(file))
            )
        end

        raise no_files_changed_error if updated_files.none?

        updated_files
      end

      private

      sig { returns(RuntimeError) }
      def no_files_changed_error
        error = RuntimeError.new("No files have changed!")
        Dependabot::ErrorReportContext.attach(
          error,
          {
            dependency_names: dependencies.map(&:name),
            dependency_files: dependency_files.map(&:name)
          }
        )
        error
      end

      sig { override.void }
      def check_required_files
        return if elm_json_files.any?

        raise "No #{MANIFEST_FILE}"
      end

      sig { params(file: Dependabot::DependencyFile).returns(T.nilable(String)) }
      def updated_elm_json_content(file)
        ElmJsonUpdater.new(
          dependencies: dependencies,
          elm_json_file: file
        ).updated_content
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def elm_json_files
        dependency_files.select { |f| f.name.end_with?(MANIFEST_FILE) }
      end
    end
  end
end

Dependabot::FileUpdaters.register("elm", Dependabot::Elm::FileUpdater)
