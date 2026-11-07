# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/package/package_release"
require "dependabot/update_checkers/cooldown_calculation"

module Dependabot
  module Package
    class CooldownDateTracker
      extend T::Sig

      sig { params(dependency: Dependabot::Dependency, ignored_versions: T::Array[String]).void }
      def initialize(dependency:, ignored_versions:)
        @dependency = dependency
        @ignored_versions = ignored_versions
        @active = T.let(false, T::Boolean)
        @language_version = T.let(nil, T.nilable(T.any(String, Dependabot::Version)))
        @enforce_requirements = T.let(false, T::Boolean)
        @prefiltered = T.let(false, T::Boolean)
        @releases = T.let({}, T::Hash[Dependabot::Package::PackageRelease, Integer])
      end

      sig { returns(T::Boolean) }
      attr_reader :active

      sig do
        params(
          language_version: T.nilable(T.any(String, Dependabot::Version)),
          requirements: T::Boolean,
          block: T.proc.returns(T::Array[Dependabot::Package::PackageRelease])
        ).returns(T::Array[Dependabot::Package::PackageRelease])
      end
      def filter(language_version:, requirements:, &block)
        @active = true
        @language_version = language_version
        @enforce_requirements = requirements

        filtered = yield
        mark_for_selected_release(filtered)
        filtered
      ensure
        @active = false
        @language_version = nil
        @enforce_requirements = false
        @releases.clear
      end

      sig do
        params(block: T.proc.returns(T::Array[Dependabot::Package::PackageRelease]))
          .returns(T::Array[Dependabot::Package::PackageRelease])
      end
      def filter_prefiltered(&block)
        @prefiltered = true
        filter(language_version: nil, requirements: false, &block)
      ensure
        @prefiltered = false
      end

      sig do
        params(
          release: Dependabot::Package::PackageRelease,
          current_version: T.nilable(Dependabot::Version),
          days: Integer
        ).void
      end
      def record(release:, current_version:, days:)
        return unless active
        return unless @prefiltered || relevant?(release, current_version)

        @releases[release] = days
      end

      private

      sig { returns(Dependabot::Dependency) }
      attr_reader :dependency

      sig { returns(T::Array[String]) }
      attr_reader :ignored_versions

      sig do
        params(
          release: Dependabot::Package::PackageRelease,
          current_version: T.nilable(Dependabot::Version)
        ).returns(T::Boolean)
      end
      def relevant?(release, current_version)
        return false if release.yanked?
        return false if current_version && release.version <= current_version
        return false if unwanted_prerelease?(release)
        return false if ignored?(release)
        return false unless language_supported?(release)

        requirements_allow?(release)
      end

      sig { params(release: Dependabot::Package::PackageRelease).returns(T::Boolean) }
      def unwanted_prerelease?(release)
        release.version.prerelease? && !wants_prerelease?
      end

      sig { returns(T::Boolean) }
      def wants_prerelease?
        return true if dependency.numeric_version&.prerelease?

        dependency.requirements.any? do |requirement|
          requirement_string = requirement.requirement_string || ""
          requirement_string.split(",").map(&:strip).any? do |part|
            version_string = part.gsub(/^\s*[!<>=~^]+\s*/, "").strip
            next false unless dependency.version_class.correct?(version_string)

            dependency.version_class.new(version_string).prerelease?
          end
        end
      end

      sig { params(release: Dependabot::Package::PackageRelease).returns(T::Boolean) }
      def ignored?(release)
        requirements = ignored_versions.flat_map do |requirement|
          dependency.requirement_class.requirements_array(requirement)
        end
        requirements.any? { |requirement| requirement.satisfied_by?(release.version) }
      end

      sig { params(release: Dependabot::Package::PackageRelease).returns(T::Boolean) }
      def language_supported?(release)
        requirement = release.language&.requirement
        !@language_version || !requirement || requirement.satisfied_by?(@language_version)
      end

      sig { params(release: Dependabot::Package::PackageRelease).returns(T::Boolean) }
      def requirements_allow?(release)
        return true unless @enforce_requirements

        dependency.requirements.filter_map(&:requirement_string).all? do |requirement_string|
          dependency.requirement_class.requirements_array(requirement_string).any? do |requirement|
            requirement.satisfied_by?(release.version)
          end
        end
      end

      sig { params(filtered: T::Array[Dependabot::Package::PackageRelease]).void }
      def mark_for_selected_release(filtered)
        return if @releases.empty?

        current_version = dependency.numeric_version
        eligible = if @prefiltered
                     filtered
                   else
                     filtered.select { |release| relevant?(release, current_version) }
                   end
        selected = (eligible + @releases.keys).max_by(&:version)
        return unless selected

        days = @releases[selected]
        return unless days

        Dependabot::UpdateCheckers::CooldownCalculation.mark_cooldown_date_unavailable(
          dependency,
          cooldown_days: days
        )
      end
    end
  end
end
