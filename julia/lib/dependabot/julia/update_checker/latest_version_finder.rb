# typed: strong
# frozen_string_literal: true

require "time"
require "dependabot/julia/package/package_details_fetcher"
require "dependabot/julia/version"
require "dependabot/update_checkers/version_filters"

module Dependabot
  module Julia
    class LatestVersionFinder
      extend T::Sig

      sig do
        params(
          dependency: Dependabot::Dependency,
          dependency_files: T::Array[Dependabot::DependencyFile],
          credentials: T::Array[Dependabot::Credential],
          ignored_versions: T::Array[String],
          security_advisories: T::Array[Dependabot::SecurityAdvisory],
          raise_on_ignored: T::Boolean,
          cooldown_config: T.nilable(T::Hash[Symbol, T.untyped]),
          custom_registries: T::Array[T::Hash[Symbol, String]]
        ).void
      end
      def initialize(
        dependency:,
        dependency_files:,
        credentials:,
        ignored_versions:,
        security_advisories:,
        raise_on_ignored:,
        cooldown_config: nil,
        custom_registries: []
      )
        @dependency = dependency
        @dependency_files = dependency_files
        @credentials = credentials
        @ignored_versions = ignored_versions
        @security_advisories = security_advisories
        @raise_on_ignored = raise_on_ignored
        @cooldown_config = cooldown_config
        @custom_registries = custom_registries
      end

      sig { returns(T.nilable(Gem::Version)) }
      def latest_version
        @latest_version ||= T.let(fetch_latest_version, T.nilable(Gem::Version))
      end

      private

      sig { returns(Dependabot::Dependency) }
      attr_reader :dependency

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      attr_reader :dependency_files

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig { returns(T::Array[String]) }
      attr_reader :ignored_versions

      sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
      attr_reader :security_advisories

      sig { returns(T::Boolean) }
      attr_reader :raise_on_ignored

      sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
      attr_reader :cooldown_config

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      attr_reader :custom_registries

      sig { returns(T.nilable(Gem::Version)) }
      def fetch_latest_version
        # Fetch all package releases using the PackageDetailsFetcher
        package_fetcher = Julia::Package::PackageDetailsFetcher.new(
          dependency: dependency,
          credentials: credentials,
          custom_registries: custom_registries
        )

        releases = package_fetcher.fetch_package_releases
        return nil if releases.empty?

        # Filter releases based on cooldown
        if cooldown_config
          releases = filter_releases_by_cooldown(releases)
          return nil if releases.empty?
        end

        # Convert to versions for further filtering
        versions = releases.map(&:version).sort

        # Filter out ignored versions
        versions = versions.reject do |version|
          ignored_versions.any?(version.to_s)
        end

        # Filter out vulnerable versions
        filtered_versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(
          versions,
          security_advisories
        )

        raise Dependabot::AllVersionsIgnored if filtered_versions.empty? && raise_on_ignored

        filtered_versions.max
      end

      sig do
        params(
          releases: T::Array[Dependabot::Package::PackageRelease]
        ).returns(T::Array[Dependabot::Package::PackageRelease])
      end
      def filter_releases_by_cooldown(releases)
        return releases unless cooldown_config
        return releases unless dependency_in_cooldown_scope?

        releases.reject do |release|
          cooldown_active_for_release?(release)
        end
      end

      sig { params(release: Dependabot::Package::PackageRelease).returns(T::Boolean) }
      def cooldown_active_for_release?(release)
        cooldown_days = determine_cooldown_days(release.version)
        return false unless cooldown_days&.positive?
        return false unless release.released_at

        # Check if enough time has passed since release
        seconds_since_release = T.cast(Time.now - release.released_at, Float)
        cooldown_seconds = cooldown_days * 24 * 60 * 60 # Convert days to seconds
        seconds_since_release < cooldown_seconds
      end

      sig { returns(T::Boolean) }
      def dependency_in_cooldown_scope?
        return true unless cooldown_config

        config = T.must(cooldown_config) # We know it's not nil due to guard above
        includes = T.cast(config[:include], T.nilable(T::Array[String]))
        excludes = T.cast(config[:exclude], T.nilable(T::Array[String]))

        # Check exclusions first
        return false if excludes&.any? { |pattern| dependency.name.match?(Regexp.new(pattern.gsub("*", ".*"))) }

        # Check inclusions (if specified, dependency must match)
        return includes.any? { |pattern| dependency.name.match?(Regexp.new(pattern.gsub("*", ".*"))) } if includes&.any?

        true # Include by default if no include patterns specified
      end

      sig { params(version: Gem::Version).returns(T.nilable(Integer)) }
      def determine_cooldown_days(version)
        return nil unless cooldown_config

        current_version = dependency.version ? Gem::Version.new(dependency.version) : nil
        return nil unless current_version

        version_bump_type = determine_version_bump_type(version, current_version)
        cooldown_days_for_bump_type(version_bump_type)
      end

      sig { params(version: Gem::Version, current_version: Gem::Version).returns(Symbol) }
      def determine_version_bump_type(version, current_version)
        v_segments = normalize_version_segments(version)
        c_segments = normalize_version_segments(current_version)

        compare_version_segments(v_segments, c_segments)
      end

      sig { params(bump_type: Symbol).returns(T.nilable(Integer)) }
      def cooldown_days_for_bump_type(bump_type)
        return nil unless cooldown_config

        config = T.must(cooldown_config) # We know it's not nil due to guard above
        case bump_type
        when :major
          T.cast(config[:semver_major_days], T.nilable(Integer)) ||
            T.cast(config[:default_days], T.nilable(Integer))
        when :minor
          T.cast(config[:semver_minor_days], T.nilable(Integer)) ||
            T.cast(config[:default_days], T.nilable(Integer))
        when :patch
          T.cast(config[:semver_patch_days], T.nilable(Integer)) ||
            T.cast(config[:default_days], T.nilable(Integer))
        else
          T.cast(config[:default_days], T.nilable(Integer))
        end
      end

      sig { params(version: Gem::Version).returns([Integer, Integer, Integer]) }
      def normalize_version_segments(version)
        [
          (version.segments[0] || 0).to_i,
          (version.segments[1] || 0).to_i,
          (version.segments[2] || 0).to_i
        ]
      end

      sig { params(v_segments: [Integer, Integer, Integer], c_segments: [Integer, Integer, Integer]).returns(Symbol) }
      def compare_version_segments(v_segments, c_segments)
        v_major, v_minor, v_patch = v_segments
        c_major, c_minor, c_patch = c_segments

        if v_major > c_major
          :major
        elsif v_minor > c_minor
          :minor
        elsif v_patch > c_patch
          :patch
        else
          :default
        end
      end
    end
  end
end
