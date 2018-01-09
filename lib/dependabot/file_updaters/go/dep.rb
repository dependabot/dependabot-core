# frozen_string_literal: true

require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    module Go
      class Dep < Dependabot::FileUpdaters::Base
        def self.updated_files_regex
          [
            /^Gopkg\.toml$/,
            /^Gopkg\.lock$/
          ]
        end

        def updated_dependency_files
          updated_files = []

          if file_changed?(manifest)
            updated_files <<
              updated_file(
                file: manifest,
                content: updated_manifest_content
              )
          end

          updated_files <<
            updated_file(file: lockfile, content: updated_lockfile_content)

          updated_files
        end

        private

        def check_required_files
          %w(Gopkg.toml Gopkg.lock).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def manifest
          @manifest ||= get_original_file("Gopkg.toml")
        end

        def lockfile
          @lockfile ||= get_original_file("Gopkg.lock")
        end

        def updated_manifest_content
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
