# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "wildcard_matcher"
require "dependabot/dependency_attribution"
require "dependabot/dependency_change"
require "dependabot/dependency_group"
require "dependabot/dependency_snapshot"

module Dependabot
  class Updater
    # GroupDependencySelector ensures consistent group dependency selection by filtering
    # dependencies to only include those that belong to the specified group and are
    # allowed by configuration. This prevents the "superset problem" where dependencies
    # outside the group were being included in group PRs during recreation or rebasing.
    #
    # Key responsibilities:
    # - Merges per-directory dependency changes with deduplication
    # - Filters dependencies to only include group-eligible ones (filter_to_group!)
    # - Detects dependency drift in updated files
    # - Provides comprehensive observability for debugging
    #
    # The class implements a two-layer filtering system:
    # 1. Group membership check via group.contains_dependency?
    # 2. Configuration compliance check via job.allowed_update?
    #
    # Note: Filtering requires the :group_membership_enforcement feature to be enabled.
    class GroupDependencySelector
      extend T::Sig

      # Maximum number of dependency names to show in logs
      MAX_DEPENDENCIES_TO_LOG = 10

      sig { returns(Dependabot::DependencyGroup) }
      attr_reader :group

      sig { returns(Dependabot::DependencySnapshot) }
      attr_reader :snapshot

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

        merged_dependencies = deduplicate_dependencies(changes_by_dir)
        all_updated_files = collect_updated_files(changes_by_dir)
        merged_change = create_merged_change(changes_by_dir, merged_dependencies, all_updated_files)

        log_merge_stats(changes_by_dir.length, merged_dependencies.length)
        merged_change
      end

      # Collect and deduplicate updated files from all directory changes
      sig do
        params(changes_by_dir: T::Array[Dependabot::DependencyChange]).returns(T::Array[Dependabot::DependencyFile])
      end
      def collect_updated_files(changes_by_dir)
        all_updated_files = T.let([], T::Array[Dependabot::DependencyFile])

        changes_by_dir.each do |change|
          all_updated_files.concat(change.updated_dependency_files)
        end

        all_updated_files.uniq { |f| [f.directory, f.name] }
      end

      # Create merged DependencyChange object using first change as template
      sig do
        params(
          changes_by_dir: T::Array[Dependabot::DependencyChange],
          merged_dependencies: T::Array[Dependabot::Dependency],
          all_updated_files: T::Array[Dependabot::DependencyFile]
        ).returns(Dependabot::DependencyChange)
      end
      def create_merged_change(changes_by_dir, merged_dependencies, all_updated_files)
        base_change = T.must(changes_by_dir.first)
        DependencyChange.new(
          job: base_change.job,
          updated_dependencies: merged_dependencies,
          updated_dependency_files: all_updated_files
        )
      end

      # Mutates the DependencyChange to keep only group-eligible updated_dependencies
      # Adds attribution metadata; emits observability.
      sig { params(dependency_change: Dependabot::DependencyChange).void }
      def filter_to_group!(dependency_change)
        return unless Dependabot::Experiments.enabled?(:group_membership_enforcement)

        Dependabot.logger.info("Applying GroupDependencySelector filtering for group '#{group.name}'")

        original_count = dependency_change.updated_dependencies.length
        group_eligible_deps, filtered_out_deps = partition_dependencies(dependency_change)

        # Mutate the dependency change to only include group-eligible dependencies
        # Clear the current array and replace with filtered dependencies
        dependency_change.updated_dependencies.clear
        dependency_change.updated_dependencies.concat(group_eligible_deps)

        # Store filtered dependencies for observability
        @filtered_dependencies = filtered_out_deps if filtered_out_deps.any?

        directory = dependency_change.job.source.directory || "."
        emit_filtering_metrics(directory, original_count, group_eligible_deps.length, filtered_out_deps.length)
        return log_filtered_dependencies(filtered_out_deps) if filtered_out_deps.any?

        Dependabot.logger.info("No dependencies were filtered out")
      end

      # Optional: compute and attach dependency drift metadata for observability
      sig { params(dependency_change: Dependabot::DependencyChange).void }
      def annotate_dependency_drift!(dependency_change)
        return unless Dependabot::Experiments.enabled?(:group_membership_enforcement)

        dependency_drift = T.let([], T::Array[String])
        directory = dependency_change.job.source.directory || "."

        # Check if any file changes reference dependencies not in updated_dependencies
        dependency_change.updated_dependency_files.each do |file|
          # Uses already-parsed dependencies from ecosystem-specific FileParser
          # to identify dependencies referenced in this file
          detected_drift = detect_file_dependency_drift(file, dependency_change.updated_dependencies)
          dependency_drift.concat(detected_drift)
        end

        return unless dependency_drift.any?

        @dependency_drift = dependency_drift
        emit_dependency_drift_metrics(directory, dependency_drift.length)
        log_dependency_drift(dependency_drift)
      end

      private

      # Deduplicate dependencies across directories using directory + name as key
      sig { params(changes_by_dir: T::Array[Dependabot::DependencyChange]).returns(T::Array[Dependabot::Dependency]) }
      def deduplicate_dependencies(changes_by_dir)
        seen_updates = T.let(Set.new, T::Set[[String, String]])
        merged_dependencies = T.let([], T::Array[Dependabot::Dependency])

        changes_by_dir.each do |change|
          directory = change.job.source.directory || "."

          Array(change.updated_dependencies).each do |dep|
            key = [directory, dep.name]
            next if seen_updates.include?(key)

            seen_updates.add(key)
            @source_directory = directory
            merged_dependencies << dep
          end
        end

        merged_dependencies
      end

      sig do
        params(dependency_change: Dependabot::DependencyChange)
          .returns([T::Array[Dependabot::Dependency], T::Array[Dependabot::Dependency]])
      end
      def partition_dependencies(dependency_change)
        group_eligible_deps = T.let([], T::Array[Dependabot::Dependency])
        filtered_out_deps = T.let([], T::Array[Dependabot::Dependency])
        directory = dependency_change.job.source.directory || "."
        job = dependency_change.job

        Array(dependency_change.updated_dependencies).each do |dep|
          # Check both group membership AND dependabot.yml configuration filters
          if group_contains_dependency?(dep, directory) && allowed_by_config?(dep, job)
            # Before including in current group, check if dependency belongs to a more specific group
            if dependency_belongs_to_more_specific_group?(dep, directory)
              # Track reason for filtering due to more specific group
              annotate_dependency_selection(dep, :belongs_to_more_specific_group)
              filtered_out_deps << dep
            else
              # Annotate with selection reason
              annotate_dependency_selection(dep, :direct)
              group_eligible_deps << dep
            end
          else
            # Track reason for filtering
            reason = determine_filtering_reason(dep, directory, job)
            annotate_dependency_selection(dep, reason)
            filtered_out_deps << dep
          end
        end

        [group_eligible_deps, filtered_out_deps]
      end

      sig { params(dep: Dependabot::Dependency, directory: String, job: Dependabot::Job).returns(Symbol) }
      def determine_filtering_reason(dep, directory, job)
        return :not_in_group unless group_contains_dependency?(dep, directory)
        return :filtered_by_config unless allowed_by_config?(dep, job)

        :unknown
      end

      sig { params(dep: Dependabot::Dependency, directory: String).returns(T::Boolean) }
      def group_contains_dependency?(dep, directory)
        # Use the group's dependency matching logic
        # First check if group has the enhanced contains_dependency? method with directory parameter
        if @group.respond_to?(:contains_dependency?)
          T.unsafe(@group).contains_dependency?(dep, directory: directory)
        else
          # Fallback to the standard contains? method
          @group.contains?(dep)
        end
      end

      # Check if dependency belongs to a more specific group than the current one
      # This prevents generic patterns (like '*') from capturing dependencies
      # that belong to more specific patterns (like 'docker*' or exact names)
      sig { params(dep: Dependabot::Dependency, directory: String).returns(T::Boolean) }
      def dependency_belongs_to_more_specific_group?(dep, directory)
        current_group_specificity = calculate_group_specificity_for_dependency(@group, dep)

        # Check all other groups in the snapshot to see if any have higher specificity
        @snapshot.groups.any? do |other_group|
          next if other_group == @group # Skip the current group

          # Check if the other group contains this dependency
          if group_contains_dependency_for_group?(other_group, dep, directory)
            other_group_specificity = calculate_group_specificity_for_dependency(other_group, dep)
            other_group_specificity > current_group_specificity
          else
            false
          end
        end
      end

      # Calculate the specificity score for a dependency within a group
      # Higher scores indicate more specific patterns
      # Exact name matches: 1000
      # Specific patterns without wildcards: 500
      # Patterns with wildcards: 100 - (wildcard_count * 10)
      # Universal wildcard '*': 1
      sig { params(group: Dependabot::DependencyGroup, dep: Dependabot::Dependency).returns(Integer) }
      def calculate_group_specificity_for_dependency(group, dep)
        # If dependency is explicitly added to the group, highest specificity
        return 1000 if group.dependencies.include?(dep)

        # Check patterns if they exist
        patterns = T.unsafe(group.rules["patterns"])
        return 500 unless patterns # No patterns means it matches everything with medium specificity

        matching_patterns = patterns.select { |pattern| WildcardMatcher.match?(pattern, dep.name) }
        return 0 if matching_patterns.empty? # Shouldn't happen if we got here, but safety

        # Find the most specific matching pattern
        matching_patterns.map do |pattern|
          calculate_pattern_specificity(pattern, dep.name)
        end.max || 0
      end

      # Calculate specificity for an individual pattern
      sig { params(pattern: String, dep_name: String).returns(Integer) }
      def calculate_pattern_specificity(pattern, dep_name)
        # Exact match gets highest score
        return 1000 if pattern == dep_name

        # Universal wildcard gets lowest score
        return 1 if pattern == "*"

        # Count wildcards and calculate specificity
        wildcard_count = pattern.count("*")
        return 500 if wildcard_count.zero? # No wildcards, exact pattern

        # Patterns with wildcards: base score minus penalty for each wildcard
        base_score = 100
        wildcard_penalty = wildcard_count * 10
        specificity = base_score - wildcard_penalty

        # Additional bonus for longer patterns (more specific context)
        length_bonus = [pattern.length - 5, 0].max # Bonus for patterns longer than 5 chars

        [specificity + length_bonus, 1].max # Minimum score of 1
      end

      # Check if a specific group contains a dependency
      # Similar to group_contains_dependency? but for any group
      sig do
        params(group: Dependabot::DependencyGroup, dep: Dependabot::Dependency, directory: String).returns(T::Boolean)
      end
      def group_contains_dependency_for_group?(group, dep, directory)
        # Use the group's dependency matching logic
        if group.respond_to?(:contains_dependency?)
          T.unsafe(group).contains_dependency?(dep, directory: directory)
        else
          # Fallback to the standard contains? method
          group.contains?(dep)
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

      sig do
        params(
          file: Dependabot::DependencyFile,
          updated_deps: T::Array[Dependabot::Dependency]
        ).returns(T::Array[String])
      end
      def detect_file_dependency_drift(file, updated_deps)
        updated_dep_names = updated_deps.to_set(&:name)

        # Find all dependencies that have requirements from this file
        # Uses the already-parsed dependencies from the ecosystem-specific FileParser
        file_dependencies = @snapshot.dependencies.select do |dep|
          dep.requirements.any? { |req| req[:file] == file.name }
        end

        # Find dependencies in the file that aren't in updated_dependencies
        file_dependencies.filter_map do |dep|
          dep.name unless updated_dep_names.include?(dep.name)
        end
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
        # Metrics functionality removed - would require service object access
        # Future implementation could emit metrics if service is made available
        Dependabot.logger.debug(
          "GroupDependencySelector filtered #{removed} dependencies " \
          "[group=#{@group.name}, ecosystem=#{@snapshot.ecosystem}, directory=#{directory}]"
        )
      end

      sig { params(directory: String, count: Integer).void }
      def emit_dependency_drift_metrics(directory, count)
        # Future implementation could emit metrics if service is made available
        Dependabot.logger.debug(
          "GroupDependencySelector detected #{count} dependency drift items " \
          "[group=#{@group.name}, ecosystem=#{@snapshot.ecosystem}, directory=#{directory}]"
        )
      end

      sig { params(filtered_deps: T::Array[Dependabot::Dependency]).void }
      def log_filtered_dependencies(filtered_deps)
        # Group dependencies by filtering reason for better logging
        grouped_deps = group_dependencies_by_reason(filtered_deps)

        not_in_group = T.must(grouped_deps[:not_in_group])
        filtered_by_config = T.must(grouped_deps[:filtered_by_config])
        belongs_to_more_specific_group = T.must(grouped_deps[:belongs_to_more_specific_group])
        other = T.must(grouped_deps[:other])

        log_dependency_group(not_in_group, "not in group") if not_in_group.any?
        log_dependency_group(filtered_by_config, "filtered by dependabot.yml config") if filtered_by_config.any?
        if belongs_to_more_specific_group.any?
          log_dependency_group(belongs_to_more_specific_group,
                               "belongs to more specific group")
        end
        log_dependency_group(other, "filtered (other reasons)") if other.any?
      end

      sig { params(filtered_deps: T::Array[Dependabot::Dependency]).returns(T::Hash[Symbol, T::Array[String]]) }
      def group_dependencies_by_reason(filtered_deps)
        grouped = {
          not_in_group: T.let([], T::Array[String]),
          filtered_by_config: T.let([], T::Array[String]),
          belongs_to_more_specific_group: T.let([], T::Array[String]),
          other: T.let([], T::Array[String])
        }

        filtered_deps.each do |dep|
          attribution = DependencyAttribution.get_attribution(dep)
          case attribution&.dig(:selection_reason)
          when :not_in_group
            grouped[:not_in_group] << dep.name
          when :filtered_by_config
            grouped[:filtered_by_config] << dep.name
          when :belongs_to_more_specific_group
            grouped[:belongs_to_more_specific_group] << dep.name
          else
            grouped[:other] << dep.name
          end
        end

        grouped
      end

      sig { params(dep_names: T::Array[String], reason: String).void }
      def log_dependency_group(dep_names, reason)
        names = dep_names.first(MAX_DEPENDENCIES_TO_LOG).join(", ")
        suffix = dep_names.length > MAX_DEPENDENCIES_TO_LOG ? " (showing first #{MAX_DEPENDENCIES_TO_LOG})" : ""

        Dependabot.logger.info(
          "Filtered dependencies #{reason}: #{names}#{suffix} " \
          "[group=#{@group.name}, ecosystem=#{@snapshot.ecosystem}, count=#{dep_names.length}]"
        )
      end

      sig { params(dependency_drift: T::Array[String]).void }
      def log_dependency_drift(dependency_drift)
        capped_drift = dependency_drift.first(MAX_DEPENDENCIES_TO_LOG)
        suffix = dependency_drift.length > MAX_DEPENDENCIES_TO_LOG ? " (showing first #{MAX_DEPENDENCIES_TO_LOG})" : ""

        Dependabot.logger.info(
          "Dependency drift detected: #{capped_drift.join(', ')}#{suffix} " \
          "[group=#{@group.name}, ecosystem=#{@snapshot.ecosystem}, dependency_drift_count=#{dependency_drift.length}]"
        )
      end
    end
  end
end
