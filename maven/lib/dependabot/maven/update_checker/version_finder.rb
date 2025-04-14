# typed: strict
# frozen_string_literal: true

require "dependabot/package/package_latest_version_finder"
require "dependabot/package/release_cooldown_options"
require "dependabot/update_checkers/version_filters"
require "dependabot/maven/package/package_details_fetcher"
require "dependabot/maven/update_checker"
require "sorbet-runtime"

module Dependabot
  module Maven
    class UpdateChecker
      class VersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        TYPE_SUFFICES = %w(jre android java native_mt agp).freeze

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            cooldown_options: T.nilable(Dependabot::Package::ReleaseCooldownOptions),
            raise_on_ignored: T::Boolean
          ).void
        end
        def initialize(dependency:, dependency_files:, credentials:, # rubocop:disable Metrics/AbcSize
                       ignored_versions:, security_advisories:,
                       cooldown_options: nil, raise_on_ignored: false)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @cooldown_options    = cooldown_options
          @raise_on_ignored    = raise_on_ignored
          @security_advisories = security_advisories
          @forbidden_urls      = T.let([], T::Array[String])
          @dependency_metadata = T.let({}, T::Hash[T.untyped, Nokogiri::XML::Document])
          @auth_headers_finder = T.let(nil, T.nilable(Utils::AuthHeadersFinder))
          @pom_repository_details = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
          @repository_finder = T.let(nil, T.nilable(Maven::FileParser::RepositoriesFinder))
          @repositories = T.let(nil, T.nilable(T::Array[T::Hash[String, T.untyped]]))
          @released_check = T.let({}, T::Hash[Version, T::Boolean])
          @package_details_fetcher = T.let(nil, T.nilable(Package::PackageDetailsFetcher))
          @package_details = T.let(nil, T.nilable(Dependabot::Package::PackageDetails))
          @latest_version_details = T.let(nil, T.nilable(T::Hash[T.untyped, T.untyped]))
          @lowest_security_fix_version_details = T.let(nil, T.nilable(T::Hash[T.untyped, T.untyped]))
        end

        sig { returns(Package::PackageDetailsFetcher) }
        def package_details_fetcher
          @package_details_fetcher ||= Package::PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials
          )
        end

        sig { override.returns(Dependabot::Package::PackageDetails) }
        def package_details
          @package_details ||= package_details_fetcher.fetch
        end

        sig { override.returns(T::Array[Dependabot::Package::PackageRelease]) }
        def available_versions
          package_details.releases.reverse
        end

        sig do
          override.params(language_version: T.nilable(T.any(String, Dependabot::Version)))
                  .returns(T.nilable(Dependabot::Version))
        end
        def fetch_latest_version(language_version: nil) # rubocop:disable Lint/UnusedMethodArgument
          latest_version_details&.fetch(:version)
        end

        sig do
          params(language_version: T.nilable(T.any(String, Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_latest_version_with_no_unlock(language_version:) # rubocop:disable Lint/UnusedMethodArgument
          latest_version_details&.fetch(:version)
        end

        sig do
          params(language_version: T.nilable(T.any(String, Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_lowest_security_fix_version(language_version:) # rubocop:disable Lint/UnusedMethodArgument
          lowest_security_fix_version_details&.fetch(:version)
        end

        sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
        def latest_version_details
          return @latest_version_details if @latest_version_details

          possible_versions = filter_prereleases(available_versions)
          possible_versions = filter_date_based_versions(possible_versions)
          possible_versions = filter_version_types(possible_versions)
          possible_versions = filter_ignored_versions(possible_versions)
          possible_versions = filter_by_cooldown(possible_versions)

          possible_versions_reverse = possible_versions.reverse

          release = possible_versions_reverse.find { |r| package_details_fetcher.released?(r.version) }
          @latest_version_details = release ? { version: release.version, source_url: release.url } : nil
          @latest_version_details
        end

        sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
        def lowest_security_fix_version_details
          return @lowest_security_fix_version_details if @lowest_security_fix_version_details

          possible_versions = filter_prereleases(available_versions)
          possible_versions = filter_date_based_versions(possible_versions)
          possible_versions = filter_version_types(possible_versions)
          possible_versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(possible_versions,
                                                                                                    security_advisories)
          possible_versions = filter_ignored_versions(possible_versions)
          possible_versions = filter_lower_versions(possible_versions)

          release = possible_versions.find { |r| package_details_fetcher.released?(r.version) }
          @lowest_security_fix_version_details = release ? { version: release.version, source_url: release.url } : nil
          @lowest_security_fix_version_details
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
        sig { returns(T::Array[String]) }
        attr_reader :forbidden_urls
        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories

        sig do
          params(possible_releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def filter_prereleases(possible_releases)
          return possible_releases if wants_prerelease?

          filtered = possible_releases.reject { |release| release.version.prerelease? }
          if possible_releases.count > filtered.count
            Dependabot.logger.info("Filtered out #{possible_releases.count - filtered.count} pre-release versions")
          end
          filtered
        end

        sig do
          params(possible_versions: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def filter_date_based_versions(possible_versions)
          return possible_versions if wants_date_based_version?

          filtered = possible_versions.reject { |release| release.version > version_class.new(1900) }
          if possible_versions.count > filtered.count
            Dependabot.logger.info("Filtered out #{possible_versions.count - filtered.count} date-based versions")
          end
          filtered
        end

        sig do
          params(possible_versions: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def filter_version_types(possible_versions)
          filtered = possible_versions.select do |release|
            matches_dependency_version_type?(release.version)
          end
          if possible_versions.count > filtered.count
            diff = possible_versions.count - filtered.count
            classifier = dependency.version&.split(/[.\-]/)&.last
            Dependabot.logger.info("Filtered out #{diff} non-#{classifier} classifier versions")
          end
          filtered
        end

        sig do
          params(possible_versions: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def filter_ignored_versions(possible_versions)
          filtered = possible_versions

          ignored_versions.each do |req|
            ignore_requirements = Maven::Requirement.requirements_array(req)
            filtered =
              filtered
              .reject do |release|
                ignore_requirements.any? do |r|
                  r.satisfied_by?(release.version)
                end
              end
          end

          if @raise_on_ignored && filter_lower_versions(filtered).empty? &&
             filter_lower_versions(possible_versions).any?
            raise AllVersionsIgnored
          end

          if possible_versions.count > filtered.count
            diff = possible_versions.count - filtered.count
            Dependabot.logger.info("Filtered out #{diff} ignored versions")
          end

          filtered
        end

        sig do
          params(possible_versions: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def filter_lower_versions(possible_versions)
          return possible_versions unless dependency.numeric_version

          possible_versions.select do |release|
            release.version > dependency.numeric_version
          end
        end

        sig { returns(T::Boolean) }
        def wants_prerelease?
          return false unless dependency.numeric_version

          dependency.numeric_version&.prerelease? || false
        end

        sig { returns(T::Boolean) }
        def wants_date_based_version?
          return false unless dependency.numeric_version

          T.must(dependency.numeric_version) >= version_class.new(100)
        end

        sig { params(comparison_version: Dependabot::Version).returns(T::Boolean) }
        def matches_dependency_version_type?(comparison_version)
          return true unless dependency.version

          current_type = dependency.version
                                   &.gsub("native-mt", "native_mt")
                                   &.split(/[.\-]/)
                                   &.find do |type|
            TYPE_SUFFICES.find { |s| type.include?(s) }
          end

          version_type = comparison_version.to_s
                                           .gsub("native-mt", "native_mt")
                                           .split(/[.\-]/)
                                           .find do |type|
            TYPE_SUFFICES.find { |s| type.include?(s) }
          end

          current_type == version_type
        end

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end
      end
    end
  end
end
