# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/utils/elixir/version"
require "dependabot/shared_helpers"

module Dependabot
  module FileUpdaters
    module Elixir
      class Hex < Base
        require_relative "hex/mixfile_updater"
        require_relative "hex/lockfile_updater"

        def self.updated_files_regex
          [
            /^mix\.exs$/,
            /^mix\.lock$/
          ]
        end

        def updated_dependency_files
          updated_files = []

          mixfiles.each do |file|
            if file_changed?(file)
              updated_files <<
                updated_file(file: file, content: updated_mixfile_content(file))
            end
          end

          if lockfile
            updated_files <<
              updated_file(file: lockfile, content: updated_lockfile_content)
          end

          updated_files
        end

        private

        def check_required_files
          raise "No mix.exs!" unless get_original_file("mix.exs")
        end

        def updated_mixfile_content(file)
          MixfileUpdater.new(
            dependencies: dependencies,
            mixfile: file
          ).updated_mixfile_content
        end

        def updated_lockfile_content
          @updated_lockfile_content ||=
            LockfileUpdater.new(
              dependencies: dependencies,
              dependency_files: dependency_files,
              credentials: credentials
            ).updated_lockfile_content
        end

        def mixfiles
          dependency_files.select { |f| f.name.end_with?("mix.exs") }
        end

        def lockfile
          @lockfile ||= get_original_file("mix.lock")
        end
      end
    end
  end
end
