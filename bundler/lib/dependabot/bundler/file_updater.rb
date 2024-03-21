# typed: false
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/bundler/native_helpers"
require "dependabot/bundler/helpers"
require "dependabot/file_updaters/vendor_updater"

module Dependabot
  module Bundler
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/gemfile_updater"
      require_relative "file_updater/gemspec_updater"
      require_relative "file_updater/lockfile_updater"

      def self.updated_files_regex
        [
          /^Gemfile$/,
          /^Gemfile\.lock$/,
          /^gems\.rb$/,
          /^gems\.locked$/,
          /^*\.gemspec$/
        ]
      end

      def updated_dependency_files
        updated_files = []

        if gemfile && file_changed?(gemfile)
          updated_files <<
            updated_file(
              file: gemfile,
              content: updated_gemfile_content(gemfile)
            )
        end

        if lockfile && dependencies.any?(&:appears_in_lockfile?)
          updated_files <<
            updated_file(file: lockfile, content: updated_lockfile_content(gemfile, lockfile))
        end

        top_level_gemspecs.each do |file|
          next unless file_changed?(file)

          updated_files <<
            updated_file(file: file, content: updated_gemspec_content(file))
        end

        updated_files += updated_evaled_gemfiles
        updated_files += updated_evaled_lockfiles

        check_updated_files(updated_files)

        base_dir = updated_files.first.directory
        vendor_updater
          .updated_vendor_cache_files(base_directory: base_dir)
          .each do |file|
          updated_files << file
        end

        updated_files
      end

      private

      # Dynamically fetch the vendor cache folder from bundler
      def vendor_cache_dir
        return @vendor_cache_dir if defined?(@vendor_cache_dir)

        @vendor_cache_dir =
          NativeHelpers.run_bundler_subprocess(
            bundler_version: bundler_version,
            function: "vendor_cache_dir",
            options: options,
            args: {
              dir: repo_contents_path
            }
          )
      end

      def vendor_updater
        Dependabot::FileUpdaters::VendorUpdater.new(
          repo_contents_path: repo_contents_path,
          vendor_dir: vendor_cache_dir
        )
      end

      def check_required_files
        file_names = dependency_files.map(&:name)

        raise "A Gemfile must be provided if a lockfile is!" if lockfile && !gemfile

        return if file_names.any? { |name| name.match?(%r{^[^/]*\.gemspec$}) }
        return if gemfile

        raise "A gemspec or Gemfile must be provided!"
      end

      def check_updated_files(updated_files)
        return if updated_files.reject { |f| dependency_files.include?(f) }.any?

        raise "No files have changed!"
      end

      def gemfile
        @gemfile ||= get_original_file("Gemfile") ||
                     get_original_file("gems.rb")
      end

      def lockfile
        @lockfile ||= get_original_file("Gemfile.lock") ||
                      get_original_file("gems.locked")
      end

      def evaled_gemfiles
        @evaled_gemfiles ||=
          dependency_files
          .reject { |f| f.name.end_with?(".gemspec") }
          .reject { |f| f.name.end_with?(".specification") }
          .reject { |f| f.name.end_with?(".lock") }
          .reject { |f| f.name.end_with?(".ruby-version") }
          .reject { |f| f.name == "Gemfile" }
          .reject { |f| f.name == "gems.rb" }
          .reject { |f| f.name == "gems.locked" }
      end

      def evaled_lockfiles
        @evaled_lockfiles ||=
          dependency_files.
          select { |f| f.name.end_with?(".lock") }.
          reject { |f| f.name == "Gemfile.lock" }
      end

      def updated_evaled_gemfiles
        updated = []
        evaled_gemfiles.each do |file|
          next unless file_changed?(file)

          updated <<
            updated_file(file: file, content: updated_gemfile_content(file))
        end
        updated
      end

      def updated_evaled_lockfiles
        return [] unless dependencies.any?(&:appears_in_lockfile?)

        updated = []
        evaled_lockfiles.each do |file|
          matching_gemfile_name = file.name.match(/.*(?=\.lock)/)[0]
          matching_gemfile = evaled_gemfiles.find { |g| g.name == matching_gemfile_name }
          matching_gemfile = gemfile if matching_gemfile.nil?

          updated <<
            updated_file(file: file, content: updated_lockfile_content(matching_gemfile, file))
        end
        updated
      end

      def updated_gemfile_content(file)
        GemfileUpdater.new(
          dependencies: dependencies,
          gemfile: file
        ).updated_gemfile_content
      end

      def updated_gemspec_content(gemspec)
        GemspecUpdater.new(
          dependencies: dependencies,
          gemspec: gemspec
        ).updated_gemspec_content
      end

      def updated_lockfile_content(gem, lock)
        @updated_lockfile_content ||=
          LockfileUpdater.new(
            gemfile: gem,
            lockfile: lock,
            dependencies: dependencies,
            dependency_files: dependency_files,
            repo_contents_path: repo_contents_path,
            credentials: credentials,
            options: options
          ).updated_lockfile_content
      end

      def top_level_gemspecs
        dependency_files
          .select { |file| file.name.end_with?(".gemspec") }
      end

      def bundler_version
        @bundler_version ||= Helpers.bundler_version(lockfile)
      end
    end
  end
end

Dependabot::FileUpdaters
  .register("bundler", Dependabot::Bundler::FileUpdater)
