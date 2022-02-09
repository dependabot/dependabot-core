# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Elm
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/elm_json_updater"

      def self.updated_files_regex
        [
          /^elm\.json$/
        ]
      end

      def updated_dependency_files
        updated_files = []

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
        return if elm_json_files.any?

        raise "No elm.json"
      end

      def updated_elm_json_content(file)
        ElmJsonUpdater.new(
          dependencies: dependencies,
          elm_json_file: file
        ).updated_content
      end

      def elm_json_files
        dependency_files.select { |f| f.name.end_with?("elm.json") }
      end
    end
  end
end

Dependabot::FileUpdaters.register("elm", Dependabot::Elm::FileUpdater)
