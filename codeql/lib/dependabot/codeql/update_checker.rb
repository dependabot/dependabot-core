# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/update_checkers/cooldown_calculation"
require "dependabot/codeql/registry_client"
require "dependabot/codeql/requirement"
require "dependabot/codeql/version"

module Dependabot
  module Codeql
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      extend T::Sig

      # Bare version, e.g. "0.9.1" (no leading operator/wildcard).
      EXACT_PIN = /\A#{Gem::Version::VERSION_PATTERN}\z/o

      # Standard comparison operators, e.g. ">= 0.9.1", "~> 0.9.1", "= 0.9.1".
      OPERATOR_REQUIREMENT = /\A(?<op>=|!=|>=|<=|>|<|~>)\s*(?<version>#{Gem::Version::VERSION_PATTERN})\z/o

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_version
        @latest_version ||= T.let(candidate_versions.max, T.nilable(Dependabot::Codeql::Version))
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version
        # CodeQL packs resolve from a registry with no build/resolution step,
        # so the latest published version is always resolvable.
        latest_version
      end

      sig { override.returns(T.nilable(T.any(String, Gem::Version))) }
      def latest_resolvable_version_with_no_unlock
        requirement_string = current_requirement_string
        return dependency.version unless requirement_string

        reqs = requirement_class.requirements_array(requirement_string)
        in_range = candidate_versions.select { |v| reqs.all? { |r| r.satisfied_by?(v) } }
        in_range.max || current_version
      end

      sig { override.returns(T::Array[Dependabot::DependencyRequirement]) }
      def updated_requirements
        new_version = latest_version
        return dependency.requirements unless new_version

        dependency.requirements.map do |req|
          requirement_string = req.requirement.to_s
          reqs = requirement_class.requirements_array(requirement_string)
          next req if reqs.all? { |r| r.satisfied_by?(new_version) }

          updated_string = updated_requirement_string(requirement_string, new_version)
          Dependabot::DependencyRequirement.create(req.merge(requirement: updated_string))
        end
      end

      private

      # Preserves the original requirement's style (caret range, exact pin, or
      # comparison operator) when bumping to a new version, instead of always
      # widening the constraint to a caret range.
      sig { params(requirement_string: String, new_version: T.any(String, Gem::Version)).returns(String) }
      def updated_requirement_string(requirement_string, new_version)
        stripped = requirement_string.strip

        return "^#{new_version}" if Requirement::CARET_REQUIREMENT.match?(stripped)
        return new_version.to_s if EXACT_PIN.match?(stripped)

        operator_match = OPERATOR_REQUIREMENT.match(stripped)
        return "#{operator_match[:op]} #{new_version}" if operator_match

        # Unrecognised/compound constraint style (e.g. comma-separated ranges):
        # fall back to a caret range as the safest, most permissive rewrite.
        "^#{new_version}"
      end

      sig { override.returns(T::Boolean) }
      def latest_version_resolvable_with_full_unlock?
        false
      end

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def updated_dependencies_after_full_unlock
        raise NotImplementedError
      end

      sig { returns(T::Array[Dependabot::Codeql::Version]) }
      def candidate_versions
        @candidate_versions ||= T.let(
          filter_by_cooldown(
            registry_client
              .tags(dependency.name)
              .select { |tag| Version.correct?(tag) }
              .map { |tag| Version.new(tag) }
              .reject { |version| version.prerelease? && !current_version_prerelease? }
              .reject { |version| ignore_requirements.any? { |req| req.satisfied_by?(version) } }
          ),
          T.nilable(T::Array[Dependabot::Codeql::Version])
        )
      end

      sig { params(versions: T::Array[Dependabot::Codeql::Version]).returns(T::Array[Dependabot::Codeql::Version]) }
      def filter_by_cooldown(versions)
        cooldown = update_cooldown
        return versions if Dependabot::UpdateCheckers::CooldownCalculation.skip_cooldown?(cooldown, dependency.name)

        release_dates = registry_client.release_dates(dependency.name)
        return versions if release_dates.empty?

        versions.reject { |version| in_cooldown?(T.must(cooldown), version, release_dates) }
      end

      sig do
        params(
          cooldown: Dependabot::Package::ReleaseCooldownOptions,
          version: Dependabot::Codeql::Version,
          release_dates: T::Hash[String, Time]
        ).returns(T::Boolean)
      end
      def in_cooldown?(cooldown, version, release_dates)
        released_at = release_dates[version.to_s]
        return false unless released_at

        days = Dependabot::UpdateCheckers::CooldownCalculation.cooldown_days_for(cooldown, current_version, version)
        Dependabot::UpdateCheckers::CooldownCalculation.within_cooldown_window?(released_at, days)
      end

      sig { returns(T::Boolean) }
      def current_version_prerelease?
        version = current_version
        version.is_a?(Gem::Version) && version.prerelease?
      end

      sig { returns(T.nilable(String)) }
      def current_requirement_string
        dependency.requirements.filter_map(&:requirement).first&.to_s
      end

      sig { returns(Dependabot::Codeql::RegistryClient) }
      def registry_client
        @registry_client ||= T.let(
          RegistryClient.new(credentials: credentials),
          T.nilable(Dependabot::Codeql::RegistryClient)
        )
      end
    end
  end
end

Dependabot::UpdateCheckers.register("codeql", Dependabot::Codeql::UpdateChecker)
