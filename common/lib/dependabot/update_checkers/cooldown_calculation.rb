# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/package/release_cooldown_options"
require "dependabot/version"

module Dependabot
  module UpdateCheckers
    # Shared utility module for cooldown period calculations.
    #
    # Provides stateless module methods used by ecosystem update checkers
    # to determine whether a release is within its cooldown window and
    # how many cooldown days apply for a given version bump.
    module CooldownCalculation
      extend T::Sig

      DAY_IN_SECONDS = T.let(24 * 60 * 60, Integer)
      DATE_UNAVAILABLE_METADATA_KEY = :cooldown_date_unavailable

      # Shared by the pull request notice and the job-level warning so both channels
      # report the same diagnostic, whether or not the update produced a pull request.
      DATE_UNAVAILABLE_NOTICE_TYPE = "cooldown_date_unavailable"
      DATE_UNAVAILABLE_TITLE = "Cooldown was not applied"
      DATE_UNAVAILABLE_DESCRIPTION =
        "Cooldown could not be applied because no publication date was available from the registry."

      sig { params(release_date: Time, cooldown_days: Integer).returns(T::Boolean) }
      def self.within_cooldown_window?(release_date, cooldown_days)
        return false if cooldown_days <= 0

        (Time.now.to_i - release_date.to_i) < (cooldown_days * DAY_IN_SECONDS)
      end

      sig do
        params(
          cooldown: Dependabot::Package::ReleaseCooldownOptions,
          current_version: T.nilable(Dependabot::Version),
          new_version: Dependabot::Version
        ).returns(Integer)
      end
      def self.cooldown_days_for(cooldown, current_version, new_version)
        return cooldown.default_days unless current_version

        cooldown.cooldown_days_for(
          current_version.semver_parts,
          new_version.semver_parts
        )
      end

      sig do
        params(
          cooldown: T.nilable(Dependabot::Package::ReleaseCooldownOptions),
          dependency_name: String,
          cooldown_enabled: T::Boolean
        ).returns(T::Boolean)
      end
      def self.skip_cooldown?(cooldown, dependency_name, cooldown_enabled: true)
        cooldown.nil? || !cooldown_enabled || !cooldown.included?(dependency_name)
      end

      sig { params(dependency: Dependabot::Dependency, cooldown_days: Integer).void }
      def self.mark_cooldown_date_unavailable(dependency, cooldown_days:)
        return unless cooldown_days.positive?

        dependency.metadata[DATE_UNAVAILABLE_METADATA_KEY] = true
      end

      sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
      def self.cooldown_date_unavailable?(dependency)
        dependency.metadata[DATE_UNAVAILABLE_METADATA_KEY] == true
      end
    end
  end
end
