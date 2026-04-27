# typed: strict
# frozen_string_literal: true

require "excon"
require "nokogiri"
require "sorbet-runtime"

require "dependabot/security_advisory"
require "dependabot/dependency"
require "dependabot/update_checkers/version_filters"
require "dependabot/update_checkers/cooldown_calculation"
require "dependabot/registry_client"
require "dependabot/package/package_details"
require "dependabot/package/release_cooldown_options"

module Dependabot
  module Package
    class PackageLatestVersionFinder
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { returns(Dependabot::Dependency) }
      attr_reader :dependency

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      attr_reader :dependency_files

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig { returns(T::Array[String]) }
      attr_reader :ignored_versions

      sig { returns(T::Array[SecurityAdvisory]) }
      attr_reader :security_advisories

      sig { returns(T.nilable(ReleaseCooldownOptions)) }
      attr_reader :cooldown_options

      sig { returns(T::Hash[Symbol, T.untyped]) }
      attr_reader :options

      sig do
        params(
          dependency: Dependabot::Dependency,
          dependency_files: T::Array[Dependabot::DependencyFile],
          credentials: T::Array[Dependabot::Credential],
          ignored_versions: T::Array[String],
          security_advisories: T::Array[Dependabot::SecurityAdvisory],
          cooldown_options: T.nilable(ReleaseCooldownOptions),
          raise_on_ignored: T::Boolean,
          options: T::Hash[Symbol, T.untyped]
        ).void
      end
      def initialize(
        dependency:,
        dependency_files:,
        credentials:,
        ignored_versions:,
        security_advisories:,
        cooldown_options: nil,
        raise_on_ignored: false,
        options: {}
      )
        @dependency          = dependency
        @dependency_files    = dependency_files
        @credentials         = credentials
        @ignored_versions    = ignored_versions
        @security_advisories = security_advisories
        @cooldown_options = cooldown_options
        @raise_on_ignored    = raise_on_ignored
        # It can be used by sub classes to pass options to the registry client
        @options             = options

        @latest_version = T.let(nil, T.nilable(Dependabot::Version))
        @latest_release = T.let(nil, T.nilable(Dependabot::Package::PackageRelease))
        @latest_version_with_no_unlock = T.let(nil, T.nilable(Dependabot::Version))
        @lowest_security_fix_version = T.let(nil, T.nilable(Dependabot::Version))
        @package_details = T.let(nil, T.nilable(Dependabot::Package::PackageDetails))
      end

      sig do
        params(language_version: T.nilable(T.any(String, Dependabot::Version)))
          .returns(T.nilable(Dependabot::Version))
      end
      def latest_version(language_version: nil)
        @latest_version ||= fetch_latest_version(language_version: language_version)
      end

      sig do
        params(language_version: T.nilable(T.any(String, Dependabot::Version)))
          .returns(T.nilable(String))
      end
      def latest_tag(language_version: nil)
        latest_release(language_version: language_version)&.tag
      end

      sig do
        params(language_version: T.nilable(T.any(String, Dependabot::Version)))
          .returns(T.nilable(Dependabot::Package::PackageRelease))
      end
      def latest_release(language_version: nil)
        @latest_release ||= fetch_latest_release(language_version: language_version)
      end

      sig do
        params(language_version: T.nilable(T.any(String, Dependabot::Version)))
          .returns(T.nilable(Dependabot::Version))
      end
      def latest_version_with_no_unlock(language_version: nil)
        @latest_version_with_no_unlock ||= fetch_latest_version_with_no_unlock(language_version: language_version)
      end

      sig do
        params(language_version: T.nilable(T.any(String, Dependabot::Version)))
          .returns(T.nilable(Dependabot::Version))
      end
      def lowest_security_fix_version(language_version: nil)
        @lowest_security_fix_version ||= fetch_lowest_security_fix_version(language_version: language_version)
      end

      sig do
        returns(T.nilable(T::Array[Dependabot::Package::PackageRelease]))
      end
      def available_versions
        package_details&.releases
      end

      protected

      sig do
        params(language_version: T.nilable(T.any(String, Dependabot::Version)))
          .returns(T.nilable(Dependabot::Version))
      end
      def fetch_latest_version_with_no_unlock(language_version:)
        releases = available_versions
        return unless releases

        releases = filter_yanked_versions(releases)
        releases = filter_by_cooldown(releases)
        releases = filter_unsupported_versions(releases, language_version)
        releases = filter_prerelease_versions(releases)
        releases = filter_ignored_versions(releases)
        releases = filter_out_of_range_versions(releases)
        releases = apply_post_fetch_latest_versions_filter(releases)
        releases.max_by(&:version)&.version
      end

      sig do
        params(releases: T::Array[Dependabot::Package::PackageRelease])
          .returns(T::Array[Dependabot::Package::PackageRelease])
      end
      def filter_yanked_versions(releases)
        filtered = releases.reject(&:yanked?)
        if releases.count > filtered.count
          Dependabot.logger.info("Filtered out #{releases.count - filtered.count} yanked versions")
        end
        filtered
      end

      sig do
        params(releases: T::Array[Dependabot::Package::PackageRelease])
          .returns(T::Array[Dependabot::Package::PackageRelease])
      end
      def filter_by_cooldown(releases)
        return releases unless cooldown_enabled?
        return releases unless cooldown_options

        filtered = releases.reject { |release| in_cooldown_period?(release) }

        if releases.count > filtered.count
          Dependabot.logger.info("Filtered out #{releases.count - filtered.count} versions due to cooldown")
        end

        # If all releases were filtered out due to cooldown and we have a current version, use it as fallback
        if filtered.empty? && !releases.empty? && dependency.version
          current_version_str = dependency.version

          Dependabot.logger.info(
            "All versions filtered by cooldown for #{dependency.name}, " \
            "falling back to current version #{current_version_str}"
          )

          # Create a PackageRelease for the current version
          current_version = version_class.new(current_version_str)
          current_release = Dependabot::Package::PackageRelease.new(
            version: current_version,
            released_at: nil,
            tag: nil
          )
          return [current_release]
        end

        filtered
      end

      sig { params(release: Dependabot::Package::PackageRelease).returns(T::Boolean) }
      def in_cooldown_period?(release)
        return false unless release.released_at

        cooldown = @cooldown_options
        return false if Dependabot::UpdateCheckers::CooldownCalculation.skip_cooldown?(
          cooldown, dependency.name, cooldown_enabled: cooldown_enabled?
        )

        current_version = version_class.correct?(dependency.version) ? version_class.new(dependency.version) : nil
        days = Dependabot::UpdateCheckers::CooldownCalculation.cooldown_days_for(
          T.must(cooldown), current_version, release.version
        )
        Dependabot::UpdateCheckers::CooldownCalculation.within_cooldown_window?(
          T.must(release.released_at), days
        )
      end

      sig do
        params(
          releases: T::Array[Dependabot::Package::PackageRelease],
          language_version: T.nilable(T.any(String, Dependabot::Version))
        )
          .returns(T::Array[Dependabot::Package::PackageRelease])
      end
      def filter_unsupported_versions(releases, language_version)
        filtered = releases.filter_map do |release|
          language_requirement = release.language&.requirement
          next release unless language_version
          next release unless language_requirement
          next unless language_requirement.satisfied_by?(language_version)

          release
        end
        if releases.count > filtered.count
          delta = releases.count - filtered.count
          Dependabot.logger.info("Filtered out #{delta} unsupported Language #{language_version} versions")
        end
        filtered
      end

      sig do
        params(releases: T::Array[Dependabot::Package::PackageRelease])
          .returns(T::Array[Dependabot::Package::PackageRelease])
      end
      def filter_prerelease_versions(releases)
        return releases if wants_prerelease?

        filtered = releases.reject { |release| release.version.prerelease? }

        if releases.count > filtered.count
          Dependabot.logger.info("Filtered out #{releases.count - filtered.count} pre-release versions")
        end

        filtered
      end

      sig do
        params(releases: T::Array[Dependabot::Package::PackageRelease])
          .returns(T::Array[Dependabot::Package::PackageRelease])
      end
      def filter_ignored_versions(releases)
        filtered = releases
                   .reject do |release|
          ignore_requirements.any? do |r|
            r.satisfied_by?(release.version)
          end
        end
        if @raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(releases).any?
          raise Dependabot::AllVersionsIgnored
        end

        if releases.count > filtered.count
          Dependabot.logger.info("Filtered out #{releases.count - filtered.count} ignored versions")
        end
        filtered
      end

      sig do
        params(releases: T::Array[Dependabot::Package::PackageRelease])
          .returns(T::Array[Dependabot::Package::PackageRelease])
      end
      def filter_lower_versions(releases)
        return releases unless dependency.numeric_version

        releases.select { |release| release.version > dependency.numeric_version }
      end

      sig do
        params(releases: T::Array[Dependabot::Package::PackageRelease])
          .returns(T::Array[Dependabot::Package::PackageRelease])
      end
      def filter_out_of_range_versions(releases)
        reqs = dependency.requirements.filter_map do |r|
          next if r.fetch(:requirement).nil?

          requirement_class.requirements_array(r.fetch(:requirement))
        end

        releases
          .select do |release|
          reqs.all? do |r|
            r.any? { |o| o.satisfied_by?(release.version) }
          end
        end
      end

      sig do
        params(
          current_version: T.nilable(Dependabot::Version),
          new_version: Dependabot::Version
        ).returns(Integer)
      end
      def cooldown_days_for(current_version, new_version)
        cooldown = @cooldown_options
        return 0 if Dependabot::UpdateCheckers::CooldownCalculation.skip_cooldown?(
          cooldown, dependency.name, cooldown_enabled: cooldown_enabled?
        )

        Dependabot::UpdateCheckers::CooldownCalculation.cooldown_days_for(
          T.must(cooldown), current_version, new_version
        )
      end

      sig { returns(T::Boolean) }
      def wants_prerelease?
        return version_class.new(dependency.version).prerelease? if dependency.version

        dependency.requirements.any? do |req|
          reqs = (req.fetch(:requirement) || "").split(",").map(&:strip)
          reqs.any? { |r| r.match?(/[A-Za-z]/) }
        end
      end

      sig { returns(T::Array[T.untyped]) }
      def ignore_requirements
        ignored_versions.flat_map { |req| requirement_class.requirements_array(req) }
      end

      sig { returns(T.class_of(Dependabot::Version)) }
      def version_class
        dependency.version_class
      end

      sig { returns(T.class_of(Dependabot::Requirement)) }
      def requirement_class
        dependency.requirement_class
      end

      private

      sig { abstract.returns(T.nilable(Dependabot::Package::PackageDetails)) }
      def package_details; end

      sig { returns(T::Boolean) }
      def cooldown_enabled?
        true
      end

      sig do
        params(language_version: T.nilable(T.any(String, Dependabot::Version)))
          .returns(T.nilable(Dependabot::Version))
      end
      def fetch_latest_version(language_version: nil)
        latest_release(language_version: language_version)&.version
      end

      sig do
        params(language_version: T.nilable(T.any(String, Dependabot::Version)))
          .returns(T.nilable(Dependabot::Package::PackageRelease))
      end
      def fetch_latest_release(language_version: nil)
        releases = available_versions
        return unless releases

        releases = filter_yanked_versions(releases)
        releases = filter_by_cooldown(releases)
        releases = filter_unsupported_versions(releases, language_version)
        releases = filter_prerelease_versions(releases)
        releases = filter_ignored_versions(releases)
        releases = apply_post_fetch_latest_versions_filter(releases)
        releases.max_by(&:version)
      end

      sig do
        params(language_version: T.nilable(T.any(String, Dependabot::Version)))
          .returns(T.nilable(Dependabot::Version))
      end
      def fetch_lowest_security_fix_version(language_version: nil)
        releases = available_versions
        return unless releases

        releases = filter_yanked_versions(releases)
        releases = filter_unsupported_versions(releases, language_version)
        # versions = filter_prerelease_versions(versions)
        releases = Dependabot::UpdateCheckers::VersionFilters
                   .filter_vulnerable_versions(
                     releases,
                     security_advisories
                   )
        releases = filter_ignored_versions(releases)
        releases = filter_lower_versions(releases)
        releases = apply_post_fetch_lowest_security_fix_versions_filter(releases)

        releases.min_by(&:version)&.version
      end

      sig do
        params(releases: T::Array[Dependabot::Package::PackageRelease])
          .returns(T::Array[Dependabot::Package::PackageRelease])
      end
      def apply_post_fetch_latest_versions_filter(releases)
        releases
      end

      sig do
        params(releases: T::Array[Dependabot::Package::PackageRelease])
          .returns(T::Array[Dependabot::Package::PackageRelease])
      end
      def apply_post_fetch_lowest_security_fix_versions_filter(releases)
        releases
      end
    end
  end
end
