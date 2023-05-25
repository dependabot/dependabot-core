# frozen_string_literal: true

# This class is responsible for tracking changes to the original files as we
# make changes
module Dependabot
  class Updater
    class GroupDependencyFileBatch
      def initialize(initial_dependency_files)
        @dependency_file_batch = initial_dependency_files.each_with_object({}) do |file, hash|
          hash[file.path] = { file: file, changed: false, changes: 0 }
        end

        @other_updated_files = {}

        Dependabot.logger.debug("Starting with '#{@dependency_file_batch.count}' dependency files:")
        debug_current_state
      end

      # Returns an array of DependencyFile objects for the current state
      def dependency_files
        @dependency_file_batch.map do |_path, data|
          data[:file]
        end
      end

      # Returns an array of DependencyFile objects that have changed at least once
      def changed_files
        @dependency_file_batch.filter_map { |_path, data| data[:file] if data[:changed] } +
          @other_updated_files.map { |_path, data| data[:file] }
      end

      # Replaces the existing files
      def merge(updated_files)
        updated_files.each do |updated_file|
          if (existing_file = @dependency_file_batch[updated_file.path])
            # The file is a dependency file we started with, let's replace the old version
            change_count = existing_file.fetch(:change_count, 0)
            @dependency_file_batch[updated_file.path] = { file: updated_file, changed: true, changes: change_count + 1 }
          elsif (existing_file = @other_updated_files[updated_file.path])
            # The file is a non-dependency file we previous modified, let's replace the old version
            change_count = existing_file.fetch(:change_count, 0)
            @other_updated_files[updated_file.path] = { file: updated_file, changed: true, changes: change_count + 1 }
          else
            # The file is new, let's add it
            verb = updated_file.deleted? ? "removed" : "added"
            Dependabot.logger.debug("File #{verb}: '#{updated_file.path}'")
            @other_updated_files[updated_file.path] = { file: updated_file, changed: true, changes: 1 }
          end
        end

        debug_current_state
      end

      def debug_current_state
        return unless Dependabot.logger.debug?

        Dependabot.logger.debug("Dependency files updated:")
        @dependency_file_batch.each{ |path, data| debug_file_hash(path, data) }

        if @other_updated_files.any?
          Dependabot.logger.debug("Other files updated:")
          @other_updated_files.each{ |path, data| debug_file_hash(path, data) }
        end
      end

      def debug_file_hash(path, data)
        changed_string = data[:changed] ? "( Changed #{data[:changes]} times )" : ""
        Dependabot.logger.debug("  - #{path} #{changed_string}")
      end
    end
  end
end
