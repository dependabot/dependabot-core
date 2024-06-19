# typed: true
# frozen_string_literal: true

require "pathname"

# This class is responsible for aggregating individual DependencyChange objects
# by tracking changes to individual files and the overall dependency list.
module Dependabot
  class Updater
    class DependencyGroupChangeBatch
      attr_reader :updated_dependencies

      def initialize(initial_dependency_files:)
        @updated_dependencies = []

        @dependency_file_batch = initial_dependency_files.each_with_object({}) do |file, hsh|
          hsh[file.path] = { file: file, updated_dependencies: [], changed: false, changes: 0 }
        end

        @vendored_dependency_batch = {}

        Dependabot.logger.debug("Starting with '#{@dependency_file_batch.count}' dependency files:")
        debug_current_file_state
      end

      # Returns an array of DependencyFile objects for the current state
      def current_dependency_files(job)
        directory = Pathname.new(job.source.directory).cleanpath.to_s

        files = @dependency_file_batch.filter_map do |_path, data|
          data[:file] if Pathname.new(data[:file].directory).cleanpath.to_s == directory
        end
        # This should be prevented in the FileFetcher, but possible due to directory cleaning
        # that all files are filtered out.
        raise "No files found for directory #{directory}" if files.empty?

        files
      end

      # Returns an array of DependencyFile objects for dependency files that have changed at least once merged with
      # and changes we've collected to vendored dependencies
      def updated_dependency_files
        @dependency_file_batch.filter_map { |_path, data| data[:file] if data[:changed] } +
          @vendored_dependency_batch.map { |_path, data| data[:file] }
      end

      def merge(dependency_change)
        if Dependabot::Experiments.enabled?(:dependency_has_directory)
          merge_file_and_dependency_changes(
            dependency_change.updated_dependencies, 
            dependency_change.updated_dependency_files
          )
        else
          merge_dependency_changes(dependency_change.updated_dependencies)
          merge_file_changes(dependency_change.updated_dependency_files)
        end

        Dependabot.logger.debug("Dependencies updated:")
        debug_updated_dependencies

        Dependabot.logger.debug("Dependency files updated:")
        debug_current_file_state
      end

      # add an updated dependency without changing any files, useful for incidental updates
      def add_updated_dependency(dependency)
        merge_dependency_changes([dependency])
      end

      private

      # We should retain a list of all dependencies that we change.
      # This list may contain duplicates if we make iterative updates to a Dependency within a single group, but
      # rather than re-write the Dependency objects to account for the changes from the lowest previous version
      # to the final version, we should defer it to the Dependabot::PullRequestCreator::MessageBuilder as a
      # presentation concern.
      def merge_dependency_changes(updated_dependencies)
        @updated_dependencies.concat(updated_dependencies)
      end

      def merge_file_changes(updated_dependency_files)
        updated_dependency_files.each do |updated_file|
          if updated_file.vendored_file?
            merge_file_to_batch(updated_file, @vendored_dependency_batch)
          else
            merge_file_to_batch(updated_file, @dependency_file_batch)
          end
        end
      end

      def merge_file_to_batch(file, batch)
        change_count = if (existing_file = batch[file.path])
                         existing_file.fetch(:change_count, 0)
                       else
                         # The file is newly encountered
                         Dependabot.logger.debug("File #{file.operation}d: '#{file.path}'")
                         0
                       end

        batch[file.path] = { file: file, changed: true, changes: change_count + 1 }
      end

      def merge_file_and_dependency_changes(updated_dependencies, updated_dependency_files)
        updated_dependency_files.each do |updated_file|
          if updated_file.vendored_file?
            merge_file_to_batch(updated_file, @vendored_dependency_batch, updated_dependencies)
          else
            merge_file_to_batch(updated_file, @dependency_file_batch, updated_dependencies)
          end
        end
      end

      def merge_file_and_dependency_changes_to_batch(file, batch, updated_dependencies)
        change_count = if (existing_file = batch[file.path])
                         existing_file.fetch(:change_count, 0)
                       else
                         # The file is newly encountered
                         Dependabot.logger.debug("File #{file.operation}d: '#{file.path}'")
                         0
                       end

        updated_dependencies_list = batch[file.path][updated_dependencies] + updated_dependencies
        batch[file.path] = { file: file, updated_dependencies: updated_dependencies_list, changed: true, changes: change_count + 1 }
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

        @dependency_file_batch.each { |path, data| debug_file_hash(path, data) }

        return unless @vendored_dependency_batch.any?

        Dependabot.logger.debug("Vendored dependency changes:")
        @vendored_dependency_batch.each { |path, data| debug_file_hash(path, data) }
      end

      def debug_file_hash(path, data)
        changed_string = data[:changed] ? "( Changed #{data[:changes]} times )" : ""
        Dependabot.logger.debug("  - #{path} #{changed_string}")
      end
    end
  end
end
