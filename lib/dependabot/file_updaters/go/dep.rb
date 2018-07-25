# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    module Go
      class Dep < Dependabot::FileUpdaters::Base
        require_relative "dep/manifest_updater"
        require_relative "dep/lockfile_updater"

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

          if lockfile
            updated_files <<
              updated_file(file: lockfile, content: updated_lockfile_content)
          end

          raise "No files changed!" if updated_files.none?

          updated_files
        end

        private

        def check_required_files
          raise "No Gopkg.toml!" unless get_original_file("Gopkg.toml")
        end

        def manifest
          @manifest ||= get_original_file("Gopkg.toml")
        end

        def lockfile
          @lockfile ||= get_original_file("Gopkg.lock")
        end

        def updated_manifest_content
          ManifestUpdater.new(
            dependencies: dependencies,
            manifest: manifest
          ).updated_manifest_content
        end

        def updated_lockfile_content
          LockfileUpdater.new(
            dependencies: dependencies,
            dependency_files: dependency_files,
            credentials: credentials
          ).updated_lockfile_content
        end
      end
    end
  end
end
