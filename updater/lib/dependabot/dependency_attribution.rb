# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

# Extension module to add attribution metadata to Dependency objects
# for group membership enforcement observability and debugging
module Dependabot
  module DependencyAttribution
    extend T::Sig

    # Selection reasons for why a dependency was included in a group update
    SELECTION_REASONS = T.let(%i(
      direct
      already_updated
      dependency_drift
    ).freeze, T::Array[Symbol])

    # Add attribution metadata to a dependency
    sig do
      params(dependency: Dependabot::Dependency, source_group: String, selection_reason: Symbol, directory: String).void
    end
    def self.annotate_dependency(dependency, source_group:, selection_reason:, directory:)
      return unless SELECTION_REASONS.include?(selection_reason)
      return unless dependency.respond_to?(:instance_variable_set)

      dependency.instance_variable_set(:@attribution_source_group, source_group)
      dependency.instance_variable_set(:@attribution_selection_reason, selection_reason)
      dependency.instance_variable_set(:@attribution_directory, directory)
      dependency.instance_variable_set(:@attribution_timestamp, Time.now.utc)
    end

    # Get attribution metadata from a dependency
    sig { params(dependency: Dependabot::Dependency).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def self.get_attribution(dependency)
      return nil unless dependency.respond_to?(:instance_variable_get)

      source_group = dependency.instance_variable_get(:@attribution_source_group)
      return nil unless source_group

      {
        source_group: source_group,
        selection_reason: dependency.instance_variable_get(:@attribution_selection_reason),
        directory: dependency.instance_variable_get(:@attribution_directory),
        timestamp: dependency.instance_variable_get(:@attribution_timestamp)
      }
    end

    # Check if a dependency has attribution metadata
    sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
    def self.attributed?(dependency)
      return false unless dependency.respond_to?(:instance_variable_get)

      !dependency.instance_variable_get(:@attribution_source_group).nil?
    end

    # Get all attributed dependencies from a collection with their metadata
    sig { params(dependencies: T::Array[Dependabot::Dependency]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.extract_attribution_data(dependencies)
      dependencies.filter_map do |dep|
        attribution = get_attribution(dep)
        next unless attribution

        {
          name: dep.name,
          version: dep.version,
          previous_version: dep.previous_version,
          **attribution
        }
      end
    end

    # Generate telemetry summary for attributed dependencies
    sig { params(dependencies: T::Array[Dependabot::Dependency]).returns(T::Hash[String, T.untyped]) }
    def self.telemetry_summary(dependencies)
      attributed_deps = dependencies.select { |dep| attributed?(dep) }

      summary = {
        total_dependencies: dependencies.length,
        attributed_dependencies: attributed_deps.length,
        attribution_coverage: attributed_deps.length.to_f / dependencies.length,
        selection_reasons: Hash.new(0),
        source_groups: Hash.new(0),
        directories: Hash.new(0)
      }

      attributed_deps.each do |dep|
        attribution = get_attribution(dep)
        next unless attribution

        summary[:selection_reasons][attribution[:selection_reason].to_s] += 1
        summary[:source_groups][attribution[:source_group]] += 1
        summary[:directories][attribution[:directory]] += 1
      end

      summary
    end
  end
end

# Extension to DependencyChange to work with attributed dependencies
module Dependabot
  class DependencyChange
    extend T::Sig

    sig { returns(T::Hash[String, T.untyped]) }
    def attribution_summary
      DependencyAttribution.telemetry_summary(updated_dependencies)
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def attribution_details
      DependencyAttribution.extract_attribution_data(updated_dependencies)
    end

    sig { returns(T::Boolean) }
    def has_attributed_dependencies?
      updated_dependencies.any? { |dep| DependencyAttribution.attributed?(dep) }
    end

    sig { returns(T::Hash[Symbol, T::Array[Dependabot::Dependency]]) }
    def dependencies_by_selection_reason
      result = Hash.new { |h, k| h[k] = [] }

      updated_dependencies.each do |dep|
        attribution = DependencyAttribution.get_attribution(dep)
        reason = attribution ? attribution[:selection_reason] : :unknown
        result[reason] << dep
      end

      result
    end

    # Get filtered/dependency drift dependencies for observability
    sig { returns(T.nilable(T::Array[Dependabot::Dependency])) }
    def filtered_dependencies
      instance_variable_get(:@filtered_dependencies)
    end

    sig { returns(T.nilable(T::Array[String])) }
    def dependency_drift
      instance_variable_get(:@dependency_drift)
    end

    sig { returns(String) }
    def humanized_with_attribution
      updated_dependencies.map do |dependency|
        base = "#{dependency.name} ( from #{dependency.humanized_previous_version} to #{dependency.humanized_version} )"

        attribution = DependencyAttribution.get_attribution(dependency)
        if attribution && Dependabot::Experiments.enabled?(:group_membership_enforcement)
          reason_info = "[#{attribution[:selection_reason]}, group: #{attribution[:source_group]}]"
          "#{base} #{reason_info}"
        else
          base
        end
      end.join(", ")
    end

    sig { void }
    def log_attribution_details
      return unless Dependabot::Experiments.enabled?(:group_membership_enforcement)
      return unless has_attributed_dependencies?

      summary = attribution_summary
      Dependabot.logger.info(
        "DependencyChange attribution summary: #{summary[:attributed_dependencies]}/#{summary[:total_dependencies]} dependencies attributed " \
        "[coverage=#{(summary[:attribution_coverage] * 100).round(1)}%]"
      )

      # Log selection reason breakdown
      if summary[:selection_reasons].any?
        reasons = summary[:selection_reasons].map { |reason, count| "#{reason}:#{count}" }.join(", ")
        Dependabot.logger.debug("Selection reasons: #{reasons}")
      end

      # Log any filtered dependencies
      if filtered_dependencies&.any?
        filtered_names = filtered_dependencies.map(&:name).join(", ")
        Dependabot.logger.debug("Filtered dependencies: #{filtered_names}")
      end

      # Log any dependency drift
      return unless dependency_drift&.any?

      Dependabot.logger.debug("Dependency drift detected: #{dependency_drift.join(', ')}")
    end
  end
end

module Dependabot
  module Updater
    class GroupDependencySelector
      private

      # Enhanced annotation method using the attribution system
      sig { params(dep: Dependabot::Dependency, reason: Symbol).void }
      def annotate_dependency_selection(dep, reason)
        directory = dep.instance_variable_get(:@source_directory) ||
                    @snapshot.current_directory ||
                    "."

        DependencyAttribution.annotate_dependency(
          dep,
          source_group: @group.name,
          selection_reason: reason,
          directory: directory
        )
      end
    end
  end
end
