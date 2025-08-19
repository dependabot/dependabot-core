# typed: true
# frozen_string_literal: true

require "pathname"
require "sorbet-runtime"
require "dependabot/updater/group_dependency_selector"

# This class is responsible for aggregating individual DependencyChange objects
# by tracking changes to individual files and the overall dependency list.
module Dependabot
  class Updater
    class DependencyGroupChangeBatch
      attr_reader :updated_dependencies

      def initialize(dependency_snapshot: nil, group: nil, job: nil)
        @updated_dependencies = []
        @group = group
        @dependency_snapshot = dependency_snapshot
        @job = job # Store job context for selector operations
        @group_dependency_selector = nil

        @dependency_file_batch = dependency_snapshot.dependency_files.each_with_object({}) do |file, hsh|
          hsh[file.path] = { file: file, changed: false, changes: 0 }
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
        merge_dependency_changes(dependency_change.updated_dependencies)
        merge_file_changes(dependency_change.updated_dependency_files)

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

      attr_reader :group
      attr_reader :dependency_snapshot

      # Get or create the group dependency selector for consistent filtering
      def group_dependency_selector
        return @group_dependency_selector if @group_dependency_selector

        @group_dependency_selector = Dependabot::Updater::GroupDependencySelector.new(
          group: group,
          dependency_snapshot: dependency_snapshot
        )
      end

      # We should retain a list of all dependencies that we change, in future we may need to account for the folder
      # in which these changes are made to permit-cross folder updates of the same dependency.
      #
      # This list may contain duplicates if we make iterative updates to a Dependency within a single group, but
      # rather than re-write the Dependency objects to account for the changes from the lowest previous version
      # to the final version, we should defer it to the Dependabot::PullRequestCreator::MessageBuilder as a
      # presentation concern.
      def merge_dependency_changes(updated_dependencies)
        if should_enforce_group_membership?
          # Route through GroupDependencySelector for consistent filtering
          filtered_dependencies = apply_group_dependency_filtering(updated_dependencies)
          @updated_dependencies.concat(filtered_dependencies)
        else
          @updated_dependencies.concat(updated_dependencies)
        end
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

      # Check if group membership enforcement should be applied
      def should_enforce_group_membership?
        Dependabot::Experiments.enabled?(:group_membership_enforcement) &&
          group && dependency_snapshot
      end

      # Apply group dependency filtering through the GroupDependencySelector
      # This ensures consistent filtering logic across the codebase
      def apply_group_dependency_filtering(updated_dependencies)
        return updated_dependencies if updated_dependencies.empty?

        # If we have a job context, use the full selector with config filtering
        return apply_selector_filtering(updated_dependencies) if @job

        # Fallback to the basic group membership filtering
        filter_dependencies_to_group(updated_dependencies)
      end

      # Use GroupDependencySelector for complete filtering (group + config)
      def apply_selector_filtering(updated_dependencies)
        # Create a temporary DependencyChange to use the selector's filtering
        dummy_files = [] # The selector doesn't mutate files, so empty is fine

        temp_change = Dependabot::DependencyChange.new(
          job: @job,
          updated_dependencies: updated_dependencies.dup,
          updated_dependency_files: dummy_files
        )

        # Apply the selector's filtering logic
        selector = group_dependency_selector
        selector.filter_to_group!(temp_change)

        # Return the filtered dependencies
        temp_change.updated_dependencies
      end

      # Filter dependencies to only include those that belong to the group
      def filter_dependencies_to_group(dependencies)
        return dependencies unless should_enforce_group_membership?

        group_eligible_deps = []
        filtered_out_deps = []

        dependencies.each do |dep|
          if group_contains_dependency?(dep)
            # Annotate dependency with group membership metadata
            annotate_dependency_for_batch(dep)
            group_eligible_deps << dep
          else
            filtered_out_deps << dep
          end
        end

        # Log filtering activity
        if filtered_out_deps.any?
          log_filtered_dependencies(filtered_out_deps)
          emit_batch_filtering_metrics(dependencies.length, group_eligible_deps.length, filtered_out_deps.length)
        end

        group_eligible_deps
      end

      # Check if a dependency belongs to the current group
      def group_contains_dependency?(dep)
        # Use the group's dependency matching logic if available
        if group.respond_to?(:contains_dependency?)
          # Determine directory context - this may need refinement based on how directory is tracked
          directory = determine_dependency_directory(dep)
          group.contains_dependency?(dep, directory: directory)
        else
          # Fallback: check if dependency name matches group patterns
          group.dependencies&.any? { |pattern| dependency_matches_pattern?(dep.name, pattern) } || false
        end
      end

      # Determine the directory context for a dependency
      # This is a placeholder - actual implementation would need to track directory context
      def determine_dependency_directory(dep)
        # This could be enhanced to track directory context throughout the batch process
        # For now, use a default or extract from dependency metadata
        dep.instance_variable_get(:@source_directory) || "."
      end

      # Simple pattern matching for dependency names
      def dependency_matches_pattern?(dep_name, pattern)
        return true if pattern == dep_name
        return true if pattern.include?("*") && File.fnmatch(pattern, dep_name)

        false
      end

      # Annotate dependency with batch-specific metadata
      def annotate_dependency_for_batch(dep)
        return unless dep.respond_to?(:instance_variable_set)

        dep.instance_variable_set(:@batch_group, group.name)
        dep.instance_variable_set(:@batch_selection_reason, :group_membership)
      end

      # Log filtered dependencies with capped output
      def log_filtered_dependencies(filtered_deps)
        capped_names = filtered_deps.first(5).map(&:name)
        suffix = filtered_deps.length > 5 ? " (and #{filtered_deps.length - 5} more)" : ""

        Dependabot.logger.debug(
          "DependencyGroupChangeBatch filtered non-group dependencies: #{capped_names.join(', ')}#{suffix} " \
          "[group=#{group.name}, ecosystem=#{dependency_snapshot.ecosystem}]"
        )
      end

      # Emit metrics for batch filtering
      def emit_batch_filtering_metrics(original_count, filtered_count, removed_count)
        return unless removed_count > 0

        # NOTE: Dependabot::Metrics may not be available in all contexts
        # Using T.unsafe to handle the potentially missing constant
        metrics_class = T.unsafe(Dependabot).const_get(:Metrics) if T.unsafe(Dependabot).const_defined?(:Metrics)
        return unless metrics_class

        metrics_class.increment(
          "dependabot.batch.filtered_out_count",
          removed_count,
          tags: {
            group: group.name,
            ecosystem: dependency_snapshot.ecosystem,
            original_count: original_count,
            filtered_count: filtered_count
          }
        )
      end

      def debug_updated_dependencies
        return unless Dependabot.logger.debug?

        @updated_dependencies.each do |dependency|
          version_change = "#{dependency.humanized_previous_version} to #{dependency.humanized_version}"
          group_info = if should_enforce_group_membership?
                         " [group=#{group.name}]"
                       else
                         ""
                       end
          Dependabot.logger.debug(" - #{dependency.name} ( #{version_change} )#{group_info}")
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
