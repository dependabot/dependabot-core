# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/npm_and_yarn/dependency_files_filterer"
require "dependabot/npm_and_yarn/sub_dependency_files_filterer"

module Dependabot
  module NpmAndYarn
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/package_json_updater"
      require_relative "file_updater/npm_lockfile_updater"
      require_relative "file_updater/yarn_lockfile_updater"

      class NoChangeError < StandardError
        def initialize(message:, error_context:)
          super(message)
          @error_context = error_context
        end

        def raven_context
          { extra: @error_context }
        end
      end

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

        if updated_files.none?
          raise NoChangeError.new(
            message: "No files were updated!",
            error_context: error_context(updated_files: updated_files)
          )
        end

        sorted_updated_files = updated_files.sort_by(&:name)
        if sorted_updated_files == filtered_dependency_files.sort_by(&:name)
          raise NoChangeError.new(
            message: "Updated files are unchanged!",
            error_context: error_context(updated_files: updated_files)
          )
        end

        updated_files
      end

      private

      def filtered_dependency_files
        @filtered_dependency_files ||=
          begin
            if dependencies.select(&:top_level?).any?
              DependencyFilesFilterer.new(
                dependency_files: dependency_files,
                updated_dependencies: dependencies
              ).files_requiring_update
            else
              SubDependencyFilesFilterer.new(
                dependency_files: dependency_files,
                updated_dependencies: dependencies
              ).files_requiring_update
            end
          end
      end

      def check_required_files
        raise "No package.json!" unless get_original_file("package.json")
      end

      def error_context(updated_files:)
        {
          dependencies: dependencies.map(&:to_h),
          updated_files: updated_files.map(&:name),
          dependency_files: dependency_files.map(&:name)
        }
      end

      def package_locks
        @package_locks ||=
          filtered_dependency_files.
          select { |f| f.name.end_with?("package-lock.json") }
      end

      def yarn_locks
        @yarn_locks ||=
          filtered_dependency_files.
          select { |f| f.name.end_with?("yarn.lock") }
      end

      def shrinkwraps
        @shrinkwraps ||=
          filtered_dependency_files.
          select { |f| f.name.end_with?("npm-shrinkwrap.json") }
      end

      def package_files
        @package_files ||=
          filtered_dependency_files.select do |f|
            f.name.end_with?("package.json")
          end
      end

      def yarn_lock_changed?(yarn_lock)
        yarn_lock.content != updated_yarn_lock_content(yarn_lock)
      end

      def package_lock_changed?(package_lock)
        package_lock.content != updated_lockfile_content(package_lock)
      end

      def shrinkwrap_changed?(shrinkwrap)
        shrinkwrap.content != updated_lockfile_content(shrinkwrap)
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
            content: updated_lockfile_content(package_lock)
          )
        end

        shrinkwraps.each do |shrinkwrap|
          next unless shrinkwrap_changed?(shrinkwrap)

          updated_files << updated_file(
            file: shrinkwrap,
            content: updated_lockfile_content(shrinkwrap)
          )
        end

        updated_files
      end

      def updated_yarn_lock_content(yarn_lock)
        @updated_yarn_lock_content ||= {}
        @updated_yarn_lock_content[yarn_lock.name] ||=
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

      def updated_lockfile_content(file)
        @updated_lockfile_content ||= {}
        @updated_lockfile_content[file.name] ||=
          NpmLockfileUpdater.new(
            lockfile: file,
            dependencies: dependencies,
            dependency_files: dependency_files,
            credentials: credentials
          ).updated_lockfile.content
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
