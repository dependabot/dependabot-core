# frozen_string_literal: true

require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    module JavaScript
      class NpmAndYarn < Dependabot::FileUpdaters::Base
        require_relative "npm_and_yarn/npmrc_builder"
        require_relative "npm_and_yarn/package_json_updater"
        require_relative "npm_and_yarn/npm_lockfile_updater"
        require_relative "npm_and_yarn/yarn_lockfile_updater"

        def self.updated_files_regex
          [
            /^package\.json$/,
            /^package-lock\.json$/,
            /^yarn\.lock$/
          ]
        end

        def updated_dependency_files
          updated_files = []

          yarn_locks.each do |yarn_lock|
            next unless yarn_lock && yarn_lock_changed?(yarn_lock)
            updated_files << updated_file(
              file: yarn_lock,
              content: updated_yarn_lock_content(yarn_lock)
            )
          end

          package_locks.each do |package_lock|
            next unless package_lock && package_lock_changed?(package_lock)
            updated_files << updated_file(
              file: package_lock,
              content: updated_package_lock_content(package_lock)
            )
          end

          updated_files += updated_package_files

          if updated_files.none? ||
             updated_files.sort_by(&:name) == dependency_files.sort_by(&:name)
            raise "No files have changed!"
          end

          updated_files
        end

        private

        UNREACHABLE_GIT = /ls-remote (?:(-h -t)|(--tags --heads)) (?<url>.*)/

        def dependency
          # For now, we'll only ever be updating a single dependency for JS
          dependencies.first
        end

        def check_required_files
          raise "No package.json!" unless get_original_file("package.json")
        end

        def package_locks
          @package_locks ||=
            dependency_files.
            select { |f| f.name.end_with?("package-lock.json") }
        end

        def yarn_locks
          @yarn_locks ||=
            dependency_files.
            select { |f| f.name.end_with?("yarn.lock") }
        end

        def package_files
          dependency_files.select { |f| f.name.end_with?("package.json") }
        end

        def yarn_lock_changed?(yarn_lock)
          yarn_lock.content != updated_yarn_lock_content(yarn_lock)
        end

        def package_lock_changed?(package_lock)
          package_lock.content != updated_package_lock_content(package_lock)
        end

        def updated_package_files
          package_files.map do |file|
            updated_content = updated_package_json_content(file)
            next if updated_content == file.content
            updated_file(file: file, content: updated_content)
          end.compact
        end

        def updated_yarn_lock_content(yarn_lock)
          yarn_lockfile_updater.updated_yarn_lock_content(yarn_lock)
        end

        def yarn_lockfile_updater
          @yarn_lockfile_updater ||=
            YarnLockfileUpdater.new(
              dependencies: dependencies,
              dependency_files: dependency_files,
              credentials: credentials
            )
        end

        def updated_package_lock_content(package_lock)
          npm_lockfile_updater.updated_package_lock_content(package_lock)
        end

        def npm_lockfile_updater
          @npm_lockfile_updater ||=
            NpmLockfileUpdater.new(
              dependencies: dependencies,
              dependency_files: dependency_files,
              credentials: credentials
            )
        end

        def updated_package_json_content(file)
          @updated_package_json_content ||= {}
          @updated_package_json_content[file.name] ||=
            PackageJsonUpdater.new(
              package_json: file,
              dependencies: dependencies
            ).updated_package_json.content
        end
      end
    end
  end
end
