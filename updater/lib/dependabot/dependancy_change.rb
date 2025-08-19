# frozen_string_literal: true

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

