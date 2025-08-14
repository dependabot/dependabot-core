# typed: strong
# frozen_string_literal: true

module Dependabot
  module Updater
    class GroupDependencySelector
      extend T::Sig

      sig { params(group: Dependabot::DependencyGroup, dependency_snapshot: Dependabot::DependencySnapshot).void }
      def initialize(group:, dependency_snapshot:)
        @group = group
        @snapshot = dependency_snapshot
      end

      # Input: array of per-directory DependencyChange objects
      # Output: single merged DependencyChange with directory-aware dedup
      sig { params(changes_by_dir: T::Array[Dependabot::DependencyChange]).returns(Dependabot::DependencyChange) }
      def merge_per_directory!(changes_by_dir)
        return changes_by_dir.first if changes_by_dir.length == 1

        # Use directory + dependency name as deduplication key
        seen_updates = {}
        merged_dependencies = []
        all_updated_files = []

        changes_by_dir.each do |change|
          directory = change.job&.source&.directory || "."

          change.updated_dependencies.each do |dep|
            key = [directory, dep.name]
            next if seen_updates.key?(key)

            seen_updates[key] = true
            # Annotate with source directory for attribution
            dep.instance_variable_set(:@source_directory, directory) if dep.respond_to?(:instance_variable_set)
            merged_dependencies << dep
          end

          all_updated_files.concat(change.updated_dependency_files || [])
        end

        # Create merged change using the first change as template
        base_change = changes_by_dir.first
        merged_change = DependencyChange.new(
          job: base_change.job,
          updated_dependencies: merged_dependencies,
          updated_dependency_files: all_updated_files.uniq { |f| [f.directory, f.name] }
        )

        log_merge_stats(changes_by_dir.length, merged_dependencies.length)
        merged_change
      end

      # Mutates the DependencyChange to keep only group-eligible updated_dependencies
      # Adds attribution metadata; emits observability.
      sig { params(dependency_change: Dependabot::DependencyChange).void }
      def filter_to_group!(dependency_change)
        return unless Dependabot::Experiments.enabled?(:group_membership_enforcement)

        original_count = dependency_change.updated_dependencies.length
        group_eligible_deps = []
        filtered_out_deps = []
        directory = dependency_change.job&.source&.directory || "."

        dependency_change.updated_dependencies.each do |dep|
          if group_contains_dependency?(dep, directory)
            # Annotate with selection reason
            annotate_dependency_selection(dep, :direct)
            group_eligible_deps << dep
          else
            filtered_out_deps << dep
          end
        end

        # Mutate the dependency change to only include group-eligible dependencies
        dependency_change.instance_variable_set(:@updated_dependencies, group_eligible_deps)

        # Store filtered dependencies for observability
        dependency_change.instance_variable_set(:@filtered_dependencies, filtered_out_deps) if filtered_out_deps.any?

        emit_filtering_metrics(directory, original_count, group_eligible_deps.length, filtered_out_deps.length)
        log_filtered_dependencies(filtered_out_deps) if filtered_out_deps.any?
      end

      # Optional: compute and attach side-effect metadata for observability
      sig { params(dependency_change: Dependabot::DependencyChange).void }
      def annotate_side_effects!(dependency_change)
        return unless Dependabot::Experiments.enabled?(:group_membership_enforcement)

        side_effects = []
        directory = dependency_change.job&.source&.directory || "."

        # Check if any file changes reference dependencies not in updated_dependencies
        dependency_change.updated_dependency_files&.each do |file|
          # This would need ecosystem-specific logic to parse file content
          # and identify referenced dependencies
          detected_side_effects = detect_file_side_effects(file, dependency_change.updated_dependencies)
          side_effects.concat(detected_side_effects)
        end

        return unless side_effects.any?

        dependency_change.instance_variable_set(:@side_effects, side_effects)
        emit_side_effect_metrics(directory, side_effects.length)
        log_side_effects(side_effects)
      end

      private

      sig { params(dep: Dependabot::Dependency, directory: String).returns(T::Boolean) }
      def group_contains_dependency?(dep, directory)
        # Use the group's dependency matching logic
        # This assumes DependencyGroup has a method to check membership
        if @group.respond_to?(:contains_dependency?)
          @group.contains_dependency?(dep, directory: directory)
        else
          # Fallback: check if dependency name matches group patterns
          @group.dependencies&.any? { |pattern| dependency_matches_pattern?(dep.name, pattern) } || false
        end
      end

      sig { params(dep_name: String, pattern: String).returns(T::Boolean) }
      def dependency_matches_pattern?(dep_name, pattern)
        # Simple pattern matching - could be enhanced with glob/regex support
        return true if pattern == dep_name
        return true if pattern.include?("*") && File.fnmatch(pattern, dep_name)

        false
      end

      sig { params(dep: Dependabot::Dependency, reason: Symbol).void }
      def annotate_dependency_selection(dep, reason)
        return unless dep.respond_to?(:instance_variable_set)

        dep.instance_variable_set(:@source_group, @group.name)
        dep.instance_variable_set(:@selection_reason, reason)
      end

      sig { params(file: T.untyped, updated_deps: T::Array[Dependabot::Dependency]).returns(T::Array[String]) }
      def detect_file_side_effects(file, updated_deps)
        # to parse lockfiles and detect transitive dependencies
        []
      end

      sig { params(dir_count: Integer, merged_count: Integer).void }
      def log_merge_stats(dir_count, merged_count)
        Dependabot.logger.info(
          "GroupDependencySelector merged #{dir_count} directory changes into #{merged_count} unique dependencies" \
          "[group=#{@group.name}, ecosystem=#{@snapshot.ecosystem}]"
        )
      end

      sig { params(directory: String, original: Integer, filtered: Integer, removed: Integer).void }
      def emit_filtering_metrics(directory, original, filtered, removed)
        return unless removed.positive?

        # Emit metrics (assuming a metrics system exists)
        return unless defined?(Dependabot::Metrics)

        Dependabot::Metrics.increment(
          "dependabot.group.filtered_out_count",
          removed,
          tags: {
            group: @group.name,
            ecosystem: @snapshot.ecosystem,
            directory: directory
          }
        )
      end

      sig { params(directory: String, count: Integer).void }
      def emit_side_effect_metrics(directory, count)
        return unless defined?(Dependabot::Metrics)

        Dependabot::Metrics.increment(
          "dependabot.group.side_effect_count",
          count,
          tags: {
            group: @group.name,
            ecosystem: @snapshot.ecosystem,
            directory: directory
          }
        )
      end

      sig { params(filtered_deps: T::Array[Dependabot::Dependency]).void }
      def log_filtered_dependencies(filtered_deps)
        Dependabot.logger.info(
          "Filtered non-group dependencies: #{filtered_deps.join(', ')}#{suffix}" \
          "[group=#{@group.name}, ecosystem=#{@snapshot.ecosystem}, filtered_count=#{filtered_deps.length}]"
        )
      end

      sig { params(side_effects: T::Array[String]).void }
      def log_side_effects(side_effects)
        capped_effects = side_effects.first(10)

        Dependabot.logger.info(
          "Side effects detected: #{capped_effects.join(', ')}#{suffix}" \
          "[group=#{@group.name}, ecosystem=#{@snapshot.ecosystem}, filtered_count=#{side_effects.length}]"
        )
      end
    end
  end
end
