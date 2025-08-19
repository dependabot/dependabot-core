# typed: strict
# frozen_string_literal: true

require "dependabot/dependency_attribution"

module Dependabot
  class Updater
    class GroupDependencySelector
      extend T::Sig

      sig { params(group: Dependabot::DependencyGroup, dependency_snapshot: Dependabot::DependencySnapshot).void }
      def initialize(group:, dependency_snapshot:)
        @group = T.let(group, Dependabot::DependencyGroup)
        @snapshot = T.let(dependency_snapshot, Dependabot::DependencySnapshot)
        @source_directory = T.let(nil, T.nilable(String))
        @updated_dependencies = T.let([], T::Array[Dependabot::Dependency])
        @filtered_dependencies = T.let(nil, T.nilable(T::Array[Dependabot::Dependency]))
        @dependency_drift = T.let(nil, T.nilable(T::Array[String]))
      end

      # Input: array of per-directory DependencyChange objects
      # Output: single merged DependencyChange with directory-aware dedup
      sig { params(changes_by_dir: T::Array[Dependabot::DependencyChange]).returns(Dependabot::DependencyChange) }
      def merge_per_directory!(changes_by_dir)
        return T.must(changes_by_dir.first) if changes_by_dir.length == 1

        # Use directory + dependency name as deduplication key
        seen_updates = T.let(Set.new, T::Set[[String, String]])
        merged_dependencies = T.let([], T::Array[Dependabot::Dependency])
        all_updated_files = T.let([], T::Array[Dependabot::DependencyFile])

        changes_by_dir.each do |change|
          directory = change.job.source.directory || "."

          change.updated_dependencies.each do |dep|
            key = [directory, dep.name]
            next if seen_updates.include?(key)

            seen_updates.add(key)

            @source_directory = directory
            merged_dependencies << dep
          end

          all_updated_files.concat(change.updated_dependency_files)
        end

        # Create merged change using the first change as template
        base_change = T.must(changes_by_dir.first)
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
        group_eligible_deps = T.let([], T::Array[Dependabot::Dependency])
        filtered_out_deps = T.let([], T::Array[Dependabot::Dependency])
        directory = dependency_change.job.source.directory || "."
        job = dependency_change.job

        dependency_change.updated_dependencies.each do |dep|
          # Check both group membership AND dependabot.yml configuration filters
          if group_contains_dependency?(dep, directory) && allowed_by_config?(dep, job)
            # Annotate with selection reason
            annotate_dependency_selection(dep, :direct)
            group_eligible_deps << dep
          else
            # Track reason for filtering
            reason = if !group_contains_dependency?(dep, directory)
                       :not_in_group
                     elsif !allowed_by_config?(dep, job)
                       :filtered_by_config
                     else
                       :unknown
                     end

            annotate_dependency_selection(dep, reason)
            filtered_out_deps << dep
          end
        end

        # Mutate the dependency change to only include group-eligible dependencies
        @updated_dependencies = group_eligible_deps

        # Store filtered dependencies for observability
        @filtered_dependencies = filtered_out_deps if filtered_out_deps.any?

        emit_filtering_metrics(directory, original_count, group_eligible_deps.length, filtered_out_deps.length)
        log_filtered_dependencies(filtered_out_deps) if filtered_out_deps.any?
      end

      # Optional: compute and attach dependency drift metadata for observability
      sig { params(dependency_change: Dependabot::DependencyChange).void }
      def annotate_dependency_drift!(dependency_change)
        return unless Dependabot::Experiments.enabled?(:group_membership_enforcement)

        dependency_drift = T.let([], T::Array[String])
        directory = dependency_change.job.source.directory || "."

        # Check if any file changes reference dependencies not in updated_dependencies
        dependency_change.updated_dependency_files.each do |file|
          # This would need ecosystem-specific logic to parse file content
          # and identify referenced dependencies
          detected_drift = detect_file_dependency_drift(file, dependency_change.updated_dependencies)
          dependency_drift.concat(detected_drift)
        end

        return unless dependency_drift.any?

        @dependency_drift = dependency_drift
        emit_dependency_drift_metrics(directory, dependency_drift.length)
        log_dependency_drift(dependency_drift)
      end

      private

      sig { params(dep: Dependabot::Dependency, directory: String).returns(T::Boolean) }
      def group_contains_dependency?(dep, directory)
        # Use the group's dependency matching logic
        # This assumes DependencyGroup has a method to check membership
        if @group.respond_to?(:contains_dependency?)
          T.unsafe(@group).contains_dependency?(dep, directory: directory)
        else
          # Fallback: check if dependency name matches group patterns
          group_deps = @group.dependencies
          return false if group_deps.nil?

          group_deps.any? { |group_dep| dependency_matches_pattern?(dep.name, group_dep.name) }
        end
      end

      # Check if dependency is allowed by dependabot.yml configuration
      # This respects ignore conditions and allowed_updates from the job
      sig { params(dep: Dependabot::Dependency, job: Dependabot::Job).returns(T::Boolean) }
      def allowed_by_config?(dep, job)
        # Check if dependency is completely ignored by looking at ignore conditions
        ignore_conditions = job.ignore_conditions_for(dep)
        return false if ignore_conditions.any?(Dependabot::Config::IgnoreCondition::ALL_VERSIONS)

        # Check if dependency is allowed by the job's allowed_updates configuration
        job.allowed_update?(dep)
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
        directory = @source_directory || "."

        DependencyAttribution.annotate_dependency(
          dep,
          source_group: @group.name,
          selection_reason: reason,
          directory: directory
        )
      end

      sig { params(_file: T.untyped, _updated_deps: T::Array[Dependabot::Dependency]).returns(T::Array[String]) }
      def detect_file_dependency_drift(_file, _updated_deps)
        # This is a placeholder - real implementation would need ecosystem-specific logic
        # to parse lockfiles and detect transitive dependencies
        []
      end

      sig { params(dir_count: Integer, merged_count: Integer).void }
      def log_merge_stats(dir_count, merged_count)
        Dependabot.logger.info(
          "GroupDependencySelector merged #{dir_count} directory changes into #{merged_count} unique dependencies " \
          "[group=#{@group.name}, ecosystem=#{@snapshot.ecosystem}]"
        )
      end

      sig { params(directory: String, _original: Integer, _filtered: Integer, removed: Integer).void }
      def emit_filtering_metrics(directory, _original, _filtered, removed)
        # NOTE: Dependabot::Metrics may not be available in all contexts
        # Using T.unsafe to handle the potentially missing constant
        metrics_class = T.unsafe(Dependabot).const_get(:Metrics) if T.unsafe(Dependabot).const_defined?(:Metrics)
        return unless metrics_class

        metrics_class.increment(
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
      def emit_dependency_drift_metrics(directory, count)
        # NOTE: Dependabot::Metrics may not be available in all contexts
        # Using T.unsafe to handle the potentially missing constant
        metrics_class = T.unsafe(Dependabot).const_get(:Metrics) if T.unsafe(Dependabot).const_defined?(:Metrics)
        return unless metrics_class

        metrics_class.increment(
          "dependabot.group.dependency_drift_count",
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
        # Group dependencies by filtering reason for better logging
        group_filtered = T.let([], T::Array[String])
        config_filtered = T.let([], T::Array[String])
        other_filtered = T.let([], T::Array[String])

        filtered_deps.each do |dep|
          # Get the attribution to understand why it was filtered
          attribution = DependencyAttribution.get_attribution(dep)
          case attribution&.dig(:selection_reason)
          when :not_in_group
            group_filtered << dep.name
          when :filtered_by_config
            config_filtered << dep.name
          else
            other_filtered << dep.name
          end
        end

        if group_filtered.any?
          names = group_filtered.first(10).join(", ")
          suffix = group_filtered.length > 10 ? " (showing first 10)" : ""
          Dependabot.logger.info(
            "Filtered dependencies not in group: #{names}#{suffix} " \
            "[group=#{@group.name}, ecosystem=#{@snapshot.ecosystem}, count=#{group_filtered.length}]"
          )
        end

        if config_filtered.any?
          names = config_filtered.first(10).join(", ")
          suffix = config_filtered.length > 10 ? " (showing first 10)" : ""
          Dependabot.logger.info(
            "Filtered dependencies by dependabot.yml config: #{names}#{suffix} " \
            "[group=#{@group.name}, ecosystem=#{@snapshot.ecosystem}, count=#{config_filtered.length}]"
          )
        end

        return unless other_filtered.any?

        names = other_filtered.first(10).join(", ")
        suffix = other_filtered.length > 10 ? " (showing first 10)" : ""
        Dependabot.logger.info(
          "Filtered dependencies (other reasons): #{names}#{suffix} " \
          "[group=#{@group.name}, ecosystem=#{@snapshot.ecosystem}, count=#{other_filtered.length}]"
        )
      end

      sig { params(dependency_drift: T::Array[String]).void }
      def log_dependency_drift(dependency_drift)
        capped_drift = dependency_drift.first(10)
        suffix = dependency_drift.length > 10 ? " (showing first 10)" : ""

        Dependabot.logger.info(
          "Dependency drift detected: #{capped_drift.join(', ')}#{suffix} " \
          "[group=#{@group.name}, ecosystem=#{@snapshot.ecosystem}, dependency_drift_count=#{dependency_drift.length}]"
        )
      end
    end
  end
end
