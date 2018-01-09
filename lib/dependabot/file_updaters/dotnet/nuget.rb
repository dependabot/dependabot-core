# frozen_string_literal: true

require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    module Dotnet
      class Nuget < Dependabot::FileUpdaters::Base
        def self.updated_files_regex
          [
            /^paket\.dependencies$/,
            /^paket\.lock$/
          ]
        end

        def updated_dependency_files
          updated_files = []

          if file_changed?(dependencies_file)
            updated_files <<
              updated_file(
                file: dependencies_file,
                content: updated_dependencies_file_content
              )
          end

          updated_files <<
            updated_file(file: lockfile, content: updated_lockfile_content)

          updated_files
        end

        private

        def check_required_files
          %w(paket.dependencies paket.lock).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def dependencies_file
          @dependencies_file ||= get_original_file("paket.dependencies")
        end

        def lockfile
          @lockfile ||= get_original_file("paket.lock")
        end

        def updated_dependencies_file_content
          # TODO: This can normally be written using regexs
        end

        def updated_lockfile_content
          # TODO: This normally needs to be written in the native language.
          # We do so by shelling out to a helper method (see other languages)
        end
      end
    end
  end
end
