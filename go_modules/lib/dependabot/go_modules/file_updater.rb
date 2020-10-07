# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module GoModules
    class FileUpdater < Dependabot::FileUpdaters::Base
      require_relative "file_updater/go_mod_updater"

      def initialize(dependencies:, dependency_files:, repo_contents_path: nil,
                     credentials:, options: {})
        super
        return unless repo_contents_path.nil?

        # masquerade repo_contents_path for GoModUpdater during transition
        tmp = Dir.mktmpdir
        Dir.chdir(tmp) do
          dependency_files.each do |file|
            File.write(file.name, file.content)
          end
          `git config --global user.email "no-reply@github.com"`
          `git config --global user.name "Dependabot"`
          `git init .`
          `git add .`
          `git commit -m'fake repo_contents_path'`
        end
        @repo_contents_path = tmp
        @repo_contents_stub = true
      end

      def self.updated_files_regex
        [
          /^go\.mod$/,
          /^go\.sum$/
        ]
      end

      def updated_dependency_files
        updated_files = []

        if go_mod && file_changed?(go_mod)
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
        end

        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      def check_required_files
        return if go_mod

        raise "No go.mod!"
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

      def file_updater
        @file_updater ||=
          GoModUpdater.new(
            dependencies: dependencies,
            credentials: credentials,
            repo_contents_path: repo_contents_path,
            directory: directory,
            tidy: !@repo_contents_stub && options.fetch(:go_mod_tidy, false)
          )
      end
    end
  end
end

Dependabot::FileUpdaters.
  register("go_modules", Dependabot::GoModules::FileUpdater)
