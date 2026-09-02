# typed: strong
# frozen_string_literal: true

require "time"
require "sorbet-runtime"
require "dependabot/package/release_cooldown_options"
require "dependabot/update_checkers/cooldown_calculation"

module Dependabot
  module UpdateCheckers
    # Cooldown filtering for resolvers whose publication dates come from git tags as strings.
    module TagCooldownFilter
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { abstract.returns(Dependabot::Dependency) }
      def dependency; end

      sig { abstract.returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions)) }
      def cooldown_options; end

      sig { params(release_date: T.nilable(String)).returns(T::Boolean) }
      def check_if_version_in_cooldown_period?(release_date)
        cooldown = cooldown_options
        return false if CooldownCalculation.skip_cooldown?(cooldown, dependency.name)

        cooldown_days = T.must(cooldown).default_days
        return false unless cooldown_days.positive?

        unless release_date&.length&.positive?
          CooldownCalculation.mark_cooldown_date_unavailable(dependency, cooldown_days: cooldown_days)
          return false
        end

        passed_seconds = Time.now.to_i - release_date_to_seconds(release_date)
        passed_seconds < cooldown_days * CooldownCalculation::DAY_IN_SECONDS
      end

      # An unparseable date is treated as long past, so it never blocks an update.
      sig { params(release_date: String).returns(Integer) }
      def release_date_to_seconds(release_date)
        Time.parse(release_date).to_i
      rescue ArgumentError => e
        Dependabot.logger.error("Invalid release date format: #{release_date} and error: #{e.message}")
        0
      end
    end
  end
end
