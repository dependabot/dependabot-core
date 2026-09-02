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

        released_at = release_date_to_seconds(release_date)
        unless released_at
          CooldownCalculation.mark_cooldown_date_unavailable(dependency, cooldown_days: cooldown_days)
          return false
        end

        (Time.now.to_i - released_at) < cooldown_days * CooldownCalculation::DAY_IN_SECONDS
      end

      # Nil when the registry gave no usable date, so the caller can flag the dependency.
      sig { params(release_date: T.nilable(String)).returns(T.nilable(Integer)) }
      def release_date_to_seconds(release_date)
        return nil unless release_date&.length&.positive?

        Time.parse(release_date).to_i
      rescue ArgumentError => e
        Dependabot.logger.error("Invalid release date format: #{release_date} and error: #{e.message}")
        nil
      end
    end
  end
end
