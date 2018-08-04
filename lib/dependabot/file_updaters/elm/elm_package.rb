# frozen_string_literal: true

require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    module Elm
      class ElmPackage < Base
        require_relative "elm_package/elm_package_updater"

        def self.updated_files_regex
          [/^elm-package\.json$/]
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

          raise "No files have changed!" if updated_files.none?
          updated_files
        end

        private

        def check_required_files
          return if get_original_file("elm-package.json")
          raise "No elm-package.json!"
        end

        def updated_elm_package_content(file)
          ElmPackageUpdater.new(
            dependencies: dependencies,
            elm_package_file: file
          ).updated_elm_package_file_content
        end

        def elm_package_files
          dependency_files.select { |f| f.name.end_with?("elm-package.json") }
        end
      end
    end
  end
end
