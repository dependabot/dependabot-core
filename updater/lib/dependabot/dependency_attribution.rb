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
      not_in_group
      filtered_by_config
      unknown
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
