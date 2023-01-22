# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/file_updaters/vendor_updater"

module Dependabot
  module GoModules
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/go_mod_updater"

      def initialize(dependencies:, dependency_files:, repo_contents_path: nil,
                     credentials:, options: {})
        super

        @goprivate = options.fetch(:goprivate, "*")
        use_repo_contents_stub if repo_contents_path.nil?
      end

      def self.updated_files_regex
        [
          /^go\.mod$/,
          /^go\.sum$/
        ]
      end

      def updated_dependency_files
        updated_files = []

        if go_mod && dependency_changed?(go_mod)
          updated_files <<
            updated_file(
              file: go_mod,
              content: file_updater.updated_go_mod_content
            )

          if go_sum && go_sum.content != file_updater.updated_go_sum_content
            updated_files <<
              updated_file(
                file: go_sum,
                content: file_updater.updated_go_sum_content
              )
          end

          vendor_updater.updated_vendor_cache_files(base_directory: directory).
            each do |file|
            updated_files << file
          end
        end

        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      def dependency_changed?(go_mod)
        # file_changed? only checks for changed requirements. Need to check for indirect dep version changes too.
        file_changed?(go_mod) || dependencies.any? { |dep| dep.previous_version != dep.version }
      end

      def check_required_files
        return if go_mod

        raise "No go.mod!"
      end

      def use_repo_contents_stub
        @repo_contents_stub = true
        @repo_contents_path = Dir.mktmpdir

        Dir.chdir(@repo_contents_path) do
          dependency_files.each do |file|
            path = File.join(@repo_contents_path, directory, file.name)
            path = Pathname.new(path).expand_path
            FileUtils.mkdir_p(path.dirname)
            File.write(path, file.content)
          end

          # Only used to create a backup git config that's reset
          SharedHelpers.with_git_configured(credentials: []) do
            `git config --global user.email "no-reply@github.com"`
            `git config --global user.name "Dependabot"`
            `git init .`
            `git add .`
            `git commit -m'fake repo_contents_path'`
          end
        end
      end

      def go_mod
        @go_mod ||= get_original_file("go.mod")
      end

      def go_sum
        @go_sum ||= get_original_file("go.sum")
      end

      def directory
        dependency_files.first.directory
      end

      def vendor_dir
        File.join(repo_contents_path, directory, "vendor")
      end

      def vendor_updater
        Dependabot::FileUpdaters::VendorUpdater.new(
          repo_contents_path: repo_contents_path,
          vendor_dir: vendor_dir
        )
      end

      def file_updater
        @file_updater ||=
          GoModUpdater.new(
            dependencies: dependencies,
            credentials: credentials,
            repo_contents_path: repo_contents_path,
            directory: directory,
            options: { tidy: tidy?, vendor: vendor?, goprivate: @goprivate }
          )
      end

      def tidy?
        !@repo_contents_stub
      end

      def vendor?
        File.exist?(File.join(vendor_dir, "modules.txt"))
      end
    end
  end
end

Dependabot::FileUpdaters.
  register("go_modules", Dependabot::GoModules::FileUpdater)
