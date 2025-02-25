# typed: strict
# frozen_string_literal: true

require "cgi"
require "excon"
require "nokogiri"
require "sorbet-runtime"

require "dependabot/security_advisory"
require "dependabot/dependency"
require "dependabot/update_checkers/version_filters"
require "dependabot/registry_client"
require "dependabot/bundler"
require "dependabot/package/package_details"

module Dependabot
  module Package
    class PackageLatestVersionFinder
      extend T::Sig
      extend T::Helpers

      abstract!

      sig { returns(Dependabot::Dependency) }
      attr_reader :dependency

      sig { returns(T::Array[T.untyped]) }
      attr_reader :dependency_files

      sig { returns(T::Array[T.untyped]) }
      attr_reader :credentials

      sig { returns(T::Array[String]) }
      attr_reader :ignored_versions

      sig { returns(T::Array[SecurityAdvisory]) }
      attr_reader :security_advisories

      sig do
        params(
          dependency: Dependabot::Dependency,
          dependency_files: T::Array[Dependabot::DependencyFile],
          credentials: T::Array[Dependabot::Credential],
          ignored_versions: T::Array[String],
          security_advisories: T::Array[Dependabot::SecurityAdvisory],
          raise_on_ignored: T::Boolean
        ).void
      end
      def initialize(
        dependency:,
        dependency_files:,
        credentials:,
        ignored_versions:,
        security_advisories:,
        raise_on_ignored: false
      )
        @dependency          = dependency
        @dependency_files    = dependency_files
        @credentials         = credentials
        @ignored_versions    = ignored_versions
        @security_advisories = security_advisories
        @raise_on_ignored    = raise_on_ignored

        @latest_version = T.let(nil, T.nilable(Dependabot::Version))
        @latest_version_with_no_unlock = T.let(nil, T.nilable(Dependabot::Version))
        @lowest_security_fix_version = T.let(nil, T.nilable(Dependabot::Version))
        @package_details = T.let(nil, T.nilable(Dependabot::Package::PackageDetails))
      end

      sig do
        params(language_version: T.nilable(T.any(String, Version)))
          .returns(T.nilable(Gem::Version))
      end
      def latest_version(language_version: nil)
        @latest_version ||= fetch_latest_version(language_version: language_version)
      end

      sig do
        params(language_version: T.nilable(T.any(String, Version)))
          .returns(T.nilable(Gem::Version))
      end
      def latest_version_with_no_unlock(language_version: nil)
        @latest_version_with_no_unlock ||= fetch_latest_version_with_no_unlock(language_version: language_version)
      end

      sig do
        params(language_version: T.nilable(T.any(String, Version)))
          .returns(T.nilable(Gem::Version))
      end
      def lowest_security_fix_version(language_version: nil)
        @lowest_security_fix_version ||= fetch_lowest_security_fix_version(language_version: language_version)
      end

      sig { abstract.returns(T.nilable(Dependabot::Package::PackageDetails)) }
      def package_details; end

      sig do
        returns(T.nilable(T::Array[Dependabot::Package::PackageRelease]))
      end
      def available_versions
        package_details&.releases
      end

      protected

      sig do
        params(language_version: T.nilable(T.any(String, Version)))
          .returns(T.nilable(Dependabot::Version))
      end
      def fetch_latest_version(language_version:)
        version_hashes = available_versions
        return unless version_hashes

        version_hashes = filter_yanked_versions(version_hashes)
        versions = filter_unsupported_versions(version_hashes, language_version)
        versions = filter_prerelease_versions(versions)
        versions = filter_ignored_versions(versions)

        versions.max
      end

      sig do
        params(language_version: T.nilable(T.any(String, Version)))
          .returns(T.nilable(Dependabot::Version))
      end
      def fetch_latest_version_with_no_unlock(language_version:)
        version_hashes = available_versions
        return unless version_hashes

        version_hashes = filter_yanked_versions(version_hashes)
        versions = filter_unsupported_versions(version_hashes, language_version)
        versions = filter_prerelease_versions(versions)
        versions = filter_ignored_versions(versions)
        versions = filter_out_of_range_versions(versions)

        versions.max
      end

      sig do
        params(language_version: T.nilable(T.any(String, Version)))
          .returns(T.nilable(Dependabot::Version))
      end
      def fetch_lowest_security_fix_version(language_version:)
        version_hashes = available_versions
        return unless version_hashes

        version_hashes = filter_yanked_versions(version_hashes)
        versions = filter_unsupported_versions(version_hashes, language_version)
        # versions = filter_prerelease_versions(versions)
        versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(
          versions,
          security_advisories
        )
        versions = filter_ignored_versions(versions)
        versions = filter_lower_versions(versions)

        versions.min
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
        params(
          releases: T::Array[Dependabot::Package::PackageRelease],
          language_version: T.nilable(T.any(String, Version))
        )
          .returns(T::Array[Dependabot::Version])
      end
      def filter_unsupported_versions(releases, language_version)
        filtered = releases.filter_map do |release|
          language_requirement = release.language&.requirement
          next release.version unless language_version
          next release.version unless language_requirement
          next unless language_requirement.satisfied_by?(language_version)

          release.version
        end
        if releases.count > filtered.count
          delta = releases.count - filtered.count
          Dependabot.logger.info("Filtered out #{delta} unsupported Language #{language_version} versions")
        end
        filtered
      end

      sig do
        params(versions_array: T::Array[Dependabot::Version])
          .returns(T::Array[Dependabot::Version])
      end
      def filter_prerelease_versions(versions_array)
        return versions_array if wants_prerelease?

        filtered = versions_array.reject(&:prerelease?)

        if versions_array.count > filtered.count
          Dependabot.logger.info("Filtered out #{versions_array.count - filtered.count} pre-release versions")
        end

        filtered
      end

      sig do
        params(versions_array: T::Array[Dependabot::Version])
          .returns(T::Array[Dependabot::Version])
      end
      def filter_ignored_versions(versions_array)
        filtered = versions_array
                   .reject { |v| ignore_requirements.any? { |r| r.satisfied_by?(v) } }
        if @raise_on_ignored && filter_lower_versions(filtered).empty? && filter_lower_versions(versions_array).any?
          raise Dependabot::AllVersionsIgnored
        end

        if versions_array.count > filtered.count
          Dependabot.logger.info("Filtered out #{versions_array.count - filtered.count} ignored versions")
        end
        filtered
      end

      sig do
        params(versions_array: T::Array[Dependabot::Version])
          .returns(T::Array[Dependabot::Version])
      end
      def filter_lower_versions(versions_array)
        return versions_array unless dependency.numeric_version

        versions_array.select { |version| version > dependency.numeric_version }
      end

      sig do
        params(versions_array: T::Array[Dependabot::Version])
          .returns(T::Array[Dependabot::Version])
      end
      def filter_out_of_range_versions(versions_array)
        reqs = dependency.requirements.filter_map do |r|
          next if r.fetch(:requirement).nil?

          requirement_class.requirements_array(r.fetch(:requirement))
        end

        versions_array
          .select { |v| reqs.all? { |r| r.any? { |o| o.satisfied_by?(v) } } }
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
    end
  end
end
