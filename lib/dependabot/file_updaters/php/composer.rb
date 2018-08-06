# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/utils/php/version"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module FileUpdaters
    module Php
      class Composer < Base
        require_relative "composer/manifest_updater"
        require_relative "composer/lockfile_updater"

        def self.updated_files_regex
          [
            /^composer\.json$/,
            /^composer\.lock$/
          ]
        end

        def updated_dependency_files
          updated_files = []

          if file_changed?(composer_json)
            updated_files <<
              updated_file(
                file: composer_json,
                content: updated_composer_json_content
              )
          end

          if lockfile
            updated_files <<
              updated_file(file: lockfile, content: updated_lockfile_content)
          end

          if updated_files.none? ||
             updated_files.sort_by(&:name) == dependency_files.sort_by(&:name)
            raise "No files have changed!"
          end

          updated_files
        end

        private

        def check_required_files
          raise "No composer.json!" unless get_original_file("composer.json")
        end

        def updated_composer_json_content
          ManifestUpdater.new(
            dependencies: dependencies,
            manifest: composer_json
          ).updated_manifest_content
        end

        def updated_lockfile_content
          @updated_lockfile_content ||=
            LockfileUpdater.new(
              dependencies: dependencies,
              dependency_files: dependency_files,
              credentials: credentials
            ).updated_lockfile_content
        end

        def composer_json
          @composer_json ||= get_original_file("composer.json")
        end

        def lockfile
          @lockfile ||= get_original_file("composer.lock")
        end
      end
    end
  end
end
