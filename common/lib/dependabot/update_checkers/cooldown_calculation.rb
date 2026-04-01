# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
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

      sig { params(release_date: Time, cooldown_days: Integer).returns(T::Boolean) }
      def self.within_cooldown_window?(release_date, cooldown_days)
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
    end
  end
end
