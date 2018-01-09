# frozen_string_literal: true

require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    module Rust
      class Cargo < Dependabot::FileUpdaters::Base
        def self.updated_files_regex
          # An array of regexes that will help Dependabot determine when it
          # might need to rebase PRs.
          [
            /^Cargo\.toml$/,
            /^Cargo\.lock$/
          ]
        end

        def updated_dependency_files
          # Returns an array of updated files. Only files that have been updated
          # should be returned.
          updated_files = []

          if file_changed?(cargo_toml)
            updated_files <<
              updated_file(
                file: cargo_toml,
                content: updated_cargo_toml_content
              )
          end

          updated_files <<
            updated_file(file: lockfile, content: updated_lockfile_content)

          updated_files
        end

        private

        def check_required_files
          %w(Cargo.toml Cargo.lock).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def cargo_toml
          @cargo_toml ||= get_original_file("Cargo.toml")
        end

        def lockfile
          @lockfile ||= get_original_file("Cargo.lock")
        end

        def updated_cargo_toml_content
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
