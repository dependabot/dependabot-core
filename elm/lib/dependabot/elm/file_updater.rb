# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Elm
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/elm_package_updater"
      require_relative "file_updater/elm_json_updater"

      def self.updated_files_regex
        [
          /^elm-package\.json$/,
          /^elm\.json$/
        ]
      end

      def updated_dependency_files
        updated_files = []

        elm_package_files.each do |file|
          next unless file_changed?(file)

          updated_files <<
            updated_file(
              file: file,
              content: updated_elm_package_content(file)
            )
        end

        elm_json_files.each do |file|
          next unless file_changed?(file)

          updated_files <<
            updated_file(
              file: file,
              content: updated_elm_json_content(file)
            )
        end

        raise "No files have changed!" if updated_files.none?

        updated_files
      end

      private

      def check_required_files
        return if elm_json_files.any? || elm_package_files.any?

        raise "No elm.json or elm-package.json!"
      end

      def updated_elm_package_content(file)
        ElmPackageUpdater.new(
          dependencies: dependencies,
          elm_package_file: file
        ).updated_elm_package_file_content
      end

      def updated_elm_json_content(file)
        ElmJsonUpdater.new(
          dependencies: dependencies,
          elm_json_file: file
        ).updated_content
      end

      def elm_package_files
        dependency_files.select { |f| f.name.end_with?("elm-package.json") }
      end

      def elm_json_files
        dependency_files.select { |f| f.name.end_with?("elm.json") }
      end
    end
  end
end

Dependabot::FileUpdaters.register("elm-package", Dependabot::Elm::FileUpdater)
Dependabot::FileUpdaters.register("elm", Dependabot::Elm::FileUpdater)
