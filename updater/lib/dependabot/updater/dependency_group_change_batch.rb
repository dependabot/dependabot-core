# frozen_string_literal: true

# This class is responsible for aggregating individual DependencyChange objects
# by tracking changes to individual files and the overall dependency list.
module Dependabot
  class Updater
    class DependencyGroupChangeBatch
      attr_reader :updated_dependencies

      def initialize(initial_dependency_files:)
        @updated_dependencies = []

        @dependency_file_batch = initial_dependency_files.each_with_object({}) do |file, hash|
          hash[file.path] = { file: file, changed: false, changes: 0 }
        end

        Dependabot.logger.debug("Starting with '#{@dependency_file_batch.count}' dependency files:")
        debug_current_state
      end

      # Returns an array of DependencyFile objects for the current state
      def current_dependency_files
        @dependency_file_batch.map do |_path, data|
          data[:file]
        end
      end

      # Returns an array of DependencyFile objects that have changed at least once
      def updated_dependency_files
        @dependency_file_batch.filter_map do |_path, data|
          data[:file] if data[:changed]
        end
      end

      def merge(dependency_change)
        # FIXME: @updated_dependencies may need to be de-duped
        #
        # To start out with, using a variant on the 'existing_pull_request'
        # logic might make sense -or- we could employ a one-and-done rule
        # where the first update to a dependency blocks subsequent changes.
        #
        # In a follow-up iteration, a 'shared workspace' could provide the
        # filtering for us assuming we iteratively make file changes for
        # each Array of dependencies in the batch and the FileUpdater tells
        # us which cannot be applied.
        @updated_dependencies.concat(dependency_change.updated_dependencies)

        dependency_change.updated_dependency_files.each do |updated_file|
          existing_file = @dependency_file_batch[updated_file.path]

          change_count = if existing_file
                           existing_file.fetch(:change_count, 0)
                         else
                           Dependabot.logger.debug("New file added: '#{updated_file.path}'")
                           0
                         end

          @dependency_file_batch[updated_file.path] = { file: updated_file, changed: true, changes: change_count + 1 }
        end

        Dependabot.logger.debug("Dependency files updated:")
        debug_current_state
      end

      def debug_current_state
        return unless Dependabot.logger.debug?

        @dependency_file_batch.each do |path, data|
          changed_string = data[:changed] ? "( Changed #{data[:changes]} times )" : ""
          Dependabot.logger.debug("  - #{path} #{changed_string}")
        end
      end
    end
  end
end
