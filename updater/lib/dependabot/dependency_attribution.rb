# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"

# Extension to add attribution metadata to Dependency objects
# for group membership enforcement observability and debugging
module Dependabot
  module DependencyAttribution
    extend T::Sig

    class SelectionReason < T::Enum
      enums do
        DIRECT = new("direct")
        ALREADY_UPDATED = new("already_updated")
        DEPENDENCY_DRIFT = new("dependency_drift")
        NOT_IN_GROUP = new("not_in_group")
        FILTERED_BY_CONFIG = new("filtered_by_config")
        BELONGS_TO_MORE_SPECIFIC_GROUP = new("belongs_to_more_specific_group")
        UNKNOWN = new("unknown")
      end

      sig { returns(Symbol) }
      def to_sym
        serialize.to_sym
      end
    end

    SELECTION_REASONS = T.let(
      %i(
        direct
        already_updated
        dependency_drift
        not_in_group
        filtered_by_config
        belongs_to_more_specific_group
        unknown
      ).freeze,
      T::Array[Symbol]
    )

    class Attribution < T::ImmutableStruct
      extend T::Sig

      const :source_group, String
      const :selection_reason, SelectionReason
      const :directory, String
      const :timestamp, Time

      sig { returns(T::Hash[Symbol, Object]) }
      def to_h
        {
          source_group: source_group,
          selection_reason: selection_reason.to_sym,
          directory: directory,
          timestamp: timestamp
        }
      end
    end

    class AttributedDependency < T::ImmutableStruct
      extend T::Sig

      const :name, String
      const :version, T.nilable(String)
      const :previous_version, T.nilable(String)
      const :attribution, Attribution

      sig { returns(T::Hash[Symbol, Object]) }
      def to_h
        result = T.let(
          {
            name: name,
            version: version,
            previous_version: previous_version
          },
          T::Hash[Symbol, Object]
        )
        result.merge(attribution.to_h)
      end
    end

    class TelemetrySummary < T::ImmutableStruct
      extend T::Sig

      const :total_dependencies, Integer
      const :attributed_dependencies, Integer
      const :attribution_coverage, Float
      const :selection_reasons, T::Hash[String, Integer]
      const :source_groups, T::Hash[String, Integer]
      const :directories, T::Hash[String, Integer]

      sig { returns(T::Hash[Symbol, Object]) }
      def to_h
        {
          total_dependencies: total_dependencies,
          attributed_dependencies: attributed_dependencies,
          attribution_coverage: attribution_coverage,
          selection_reasons: selection_reasons,
          source_groups: source_groups,
          directories: directories
        }
      end
    end

    sig do
      params(dependency: Dependabot::Dependency, source_group: String, selection_reason: Symbol, directory: String).void
    end
    def self.annotate_dependency(dependency, source_group:, selection_reason:, directory:)
      reason = SelectionReason.try_deserialize(selection_reason.to_s)
      return unless reason

      dependency.attribution_source_group = source_group
      dependency.attribution_selection_reason = reason.to_sym
      dependency.attribution_directory = directory
      dependency.attribution_timestamp = Time.now.utc
    end

    sig { params(dependency: Dependabot::Dependency).returns(T.nilable(Attribution)) }
    def self.get_attribution(dependency)
      source_group = dependency.attribution_source_group
      selection_reason = dependency.attribution_selection_reason
      directory = dependency.attribution_directory
      timestamp = dependency.attribution_timestamp
      return unless source_group && selection_reason && directory && timestamp

      reason = SelectionReason.try_deserialize(selection_reason.to_s)
      return unless reason

      Attribution.new(
        source_group: source_group,
        selection_reason: reason,
        directory: directory,
        timestamp: timestamp
      )
    end

    sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
    def self.attributed?(dependency)
      !get_attribution(dependency).nil?
    end

    sig do
      params(dependencies: T::Array[Dependabot::Dependency])
        .returns(T::Array[AttributedDependency])
    end
    def self.extract_attribution_data(dependencies)
      dependencies.filter_map do |dep|
        attribution = get_attribution(dep)
        next unless attribution

        AttributedDependency.new(
          name: dep.name,
          version: dep.version,
          previous_version: dep.previous_version,
          attribution: attribution
        )
      end
    end

    sig { params(dependencies: T::Array[Dependabot::Dependency]).returns(TelemetrySummary) }
    def self.telemetry_summary(dependencies)
      attributed_deps = dependencies.select { |dep| attributed?(dep) }
      total_count = dependencies.length
      attributed_count = attributed_deps.length

      selection_reasons = T.let(Hash.new(0), T::Hash[String, Integer])
      source_groups = T.let(Hash.new(0), T::Hash[String, Integer])
      directories = T.let(Hash.new(0), T::Hash[String, Integer])

      attributed_deps.each do |dep|
        attribution = get_attribution(dep)
        next unless attribution

        reason = attribution.selection_reason.serialize
        increment(selection_reasons, reason)
        increment(source_groups, attribution.source_group)
        increment(directories, attribution.directory)
      end

      TelemetrySummary.new(
        total_dependencies: total_count,
        attributed_dependencies: attributed_count,
        attribution_coverage: total_count.zero? ? 0.0 : attributed_count.to_f / total_count,
        selection_reasons: selection_reasons,
        source_groups: source_groups,
        directories: directories
      )
    end

    sig { params(counts: T::Hash[String, Integer], key: String).void }
    def self.increment(counts, key)
      counts[key] = counts.fetch(key, 0) + 1
    end
    private_class_method :increment
  end
end
