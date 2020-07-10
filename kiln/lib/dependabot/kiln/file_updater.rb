# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"

module Dependabot
  module Kiln
    class FileUpdater < Dependabot::FileUpdaters::Base
      def initialize(dependencies:, lockfile:, dependency_files:, credentials:)
        @lockfile = lockfile
        super dependencies: dependencies, dependency_files: dependency_files, credentials: credentials
      end

      def self.updated_files_regex
        [
            /^Kilnfile\.lock$/
        ]
      end

      def updated_dependency_files
        updated_files = []

        if lockfile && lockfile.content != updated_lockfile_content
          updated_files <<
              updated_file(
                  file: lockfile,
                  content: ""
              #content: file_updater.updated_lockfile_content
              )
        end
        # raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      def file_updater
        @file_updater ||=
            FileUpdater.new(
                dependencies: dependencies,
                dependency_files: dependency_files,
                lockfile: lockfile,
                credentials: credentials
            )
      end

      def lockfile
        @lockfile ||= get_original_file("Kilnfile.lock")
      end

      def updated_lockfile_content
        ""
      end

      def check_required_files
        raise "No Kilnfile.lock!" unless lockfile
      end
    end
  end
end

Dependabot::FileUpdaters.
    register("kiln", Dependabot::Kiln::FileUpdater)
