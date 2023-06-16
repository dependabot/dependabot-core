# frozen_string_literal: true

# This class is responsible for aggregating individual DependencyChange objects
# by tracking changes to individual files and the overall dependency list.
module Dependabot
  class Updater
    class DependencyGroupChangeBatch
      attr_reader :updated_dependencies

      def initialize(initial_dependency_files:)
        @updated_dependencies = []

        @dependency_file_batch = initial_dependency_files.each_with_object({}) do |file, hsh|
          hsh[file.path] = { file: file, changed: false, changes: 0 }
        end

        Dependabot.logger.debug("Starting with '#{@dependency_file_batch.count}' dependency files:")
        debug_current_file_state
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
        merge_dependency_changes(dependency_change.updated_dependencies)
        merge_file_changes(dependency_change.updated_dependency_files)

        Dependabot.logger.debug("Dependencies updated:")
        debug_updated_dependencies

        Dependabot.logger.debug("Dependency files updated:")
        debug_current_file_state
      end

      private

      # We should retain a list of all dependencies that we change, in future we may need to account for the folder
      # in which these changes are made to permit-cross folder updates of the same dependency.
      #
      # This list may contain duplicates if we make iterative updates to a Dependency within a single group, but
      # rather than re-write the Dependency objects to account for the changes from the lowest previous version
      # to the final version, we should defer it to the Dependabot::PullRequestCreator::MessageBuilder as a
      # presentation concern.
      def merge_dependency_changes(updated_dependencies)
        @updated_dependencies.concat(updated_dependencies)
      end

      def merge_file_changes(updated_dependency_files)
        updated_dependency_files.each do |updated_file|
          existing_file = @dependency_file_batch[updated_file.path]

          change_count = if existing_file
                           existing_file.fetch(:change_count, 0)
                         else
                           Dependabot.logger.debug("File #{updated_file.operation}d: '#{updated_file.path}'")
                           0
                         end

          @dependency_file_batch[updated_file.path] = { file: updated_file, changed: true, changes: change_count + 1 }
        end
      end

      def debug_updated_dependencies
        return unless Dependabot.logger.debug?

        @updated_dependencies.each do |dependency|
          version_change = "#{dependency.humanized_previous_version} to #{dependency.humanized_version}"
          Dependabot.logger.debug(" - #{dependency.name} ( #{version_change} )")
        end
      end

      def debug_current_file_state
        return unless Dependabot.logger.debug?

        @dependency_file_batch.each do |path, data|
          changed_string = data[:changed] ? "( Changed #{data[:changes]} times )" : ""
          Dependabot.logger.debug("  - #{path} #{changed_string}")
        end
      end
    end
  end
end
