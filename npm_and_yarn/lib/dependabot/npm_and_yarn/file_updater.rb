# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module NpmAndYarn
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/package_json_updater"
      require_relative "file_updater/npm_lockfile_updater"
      require_relative "file_updater/yarn_lockfile_updater"

      def self.updated_files_regex
        [
          /^package\.json$/,
          /^package-lock\.json$/,
          /^npm-shrinkwrap\.json$/,
          /^yarn\.lock$/
        ]
      end

      def updated_dependency_files
        updated_files = []

        updated_files += updated_manifest_files
        updated_files += updated_lockfiles

        if updated_files.none? ||
           updated_files.sort_by(&:name) == dependency_files.sort_by(&:name)
          raise "No files have changed!"
        end

        updated_files
      end

      private

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

      def shrinkwraps
        @shrinkwraps ||=
          dependency_files.
          select { |f| f.name.end_with?("npm-shrinkwrap.json") }
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

      def shrinkwrap_changed?(shrinkwrap)
        shrinkwrap.content != updated_package_lock_content(shrinkwrap)
      end

      def updated_manifest_files
        package_files.map do |file|
          updated_content = updated_package_json_content(file)
          next if updated_content == file.content

          updated_file(file: file, content: updated_content)
        end.compact
      end

      def updated_lockfiles
        updated_files = []

        yarn_locks.each do |yarn_lock|
          next unless yarn_lock_changed?(yarn_lock)

          updated_files << updated_file(
            file: yarn_lock,
            content: updated_yarn_lock_content(yarn_lock)
          )
        end

        package_locks.each do |package_lock|
          next unless package_lock_changed?(package_lock)

          updated_files << updated_file(
            file: package_lock,
            content: updated_package_lock_content(package_lock)
          )
        end

        shrinkwraps.each do |shrinkwrap|
          next unless shrinkwrap_changed?(shrinkwrap)

          updated_files << updated_file(
            file: shrinkwrap,
            content: updated_shrinkwrap_content(shrinkwrap)
          )
        end

        updated_files
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
        npm_lockfile_updater.updated_lockfile_content(package_lock)
      end

      def updated_shrinkwrap_content(shrinkwrap)
        npm_lockfile_updater.updated_lockfile_content(shrinkwrap)
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

Dependabot::FileUpdaters.
  register("npm_and_yarn", Dependabot::NpmAndYarn::FileUpdater)
