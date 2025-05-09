# typed: true
# frozen_string_literal: true

require "nokogiri"
require "dependabot/shared_helpers"
require "dependabot/update_checkers/version_filters"
require "dependabot/gradle/file_parser/repositories_finder"
require "dependabot/gradle/update_checker"
require "dependabot/gradle/version"
require "dependabot/gradle/requirement"
require "dependabot/maven/utils/auth_headers_finder"
require "sorbet-runtime"
require "dependabot/gradle/package/package_details_fetcher"
require "dependabot/package/package_latest_version_finder"

module Dependabot
  module Gradle
    class UpdateChecker
      class VersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        KOTLIN_PLUGIN_REPO_PREFIX = "org.jetbrains.kotlin"
        TYPE_SUFFICES = %w(jre android java native_mt agp).freeze

        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions:, raise_on_ignored: false,
                       security_advisories:)
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @raise_on_ignored    = raise_on_ignored
          @security_advisories = security_advisories
          @forbidden_urls      = []
        end

        def latest_version_details
          possible_versions = package_release(versions)

          possible_versions = filter_prerelease_versions(possible_versions)
          possible_versions = filter_date_based_versions(possible_versions)
          possible_versions = filter_version_types(possible_versions)
          possible_versions = filter_ignored_versions(possible_versions)

          return unless possible_versions.any?

          { version: possible_versions.max_by(&:version)&.version,
            source_url: possible_versions.max_by(&:version)&.url }
        end

        def lowest_security_fix_version_details
          possible_versions = package_release(versions)

          possible_versions = filter_prerelease_versions(possible_versions)
          possible_versions = filter_date_based_versions(possible_versions)
          possible_versions = filter_version_types(possible_versions)
          possible_versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(possible_versions,
                                                                                                    security_advisories)
          possible_versions = filter_ignored_versions(possible_versions)
          possible_versions = filter_lower_versions(possible_versions)

          return unless possible_versions.any?

          { version: possible_versions.min_by(&:version)&.version,
            source_url: possible_versions.min_by(&:version)&.url }
        end

        def versions
          Package::PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            forbidden_urls: forbidden_urls
          ).fetch_available_versions
        end

        private

        attr_reader :dependency
        attr_reader :dependency_files
        attr_reader :credentials
        attr_reader :ignored_versions
        attr_reader :forbidden_urls
        attr_reader :security_advisories

        sig { params(possible_versions: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
        def filter_date_based_versions(possible_versions)
          return possible_versions if wants_date_based_version?

          filtered = possible_versions.reject { |release| release.version > version_class.new(1900) }
          if possible_versions.count > filtered.count
            Dependabot.logger.info("Filtered out #{possible_versions.count - filtered.count} date-based versions")
          end
          filtered
        end

        sig { params(possible_versions: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
        def filter_version_types(possible_versions)
          filtered = possible_versions.select { |release| matches_dependency_version_type?(release.version) }
          if possible_versions.count > filtered.count
            diff = possible_versions.count - filtered.count
            classifier = dependency.version.split(/[.\-]/).last
            Dependabot.logger.info("Filtered out #{diff} non-#{classifier} classifier versions")
          end
          filtered
        end

        def package_release(version)
          package_releases = []

          version.map do |info|
            package_releases << Dependabot::Package::PackageRelease.new(
              version: info[:version],
              released_at: info[:released_at],
              url: info[:source_url]
            )
          end
          package_releases
        end

        sig { returns(Package::PackageDetailsFetcher) }
        def package_details_fetcher
          @package_details_fetcher ||= Package::PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials
          )
        end

        sig { params(possible_versions: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
        def filter_ignored_versions(possible_versions)
          filtered = possible_versions

          ignored_versions.each do |req|
            ignore_requirements = Gradle::Requirement.requirements_array(req)
            filtered =
              filtered
              .reject { |v| ignore_requirements.any? { |r| r.satisfied_by?(v.version) } }
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

        def wants_prerelease?
          return false unless dependency.numeric_version

          dependency.numeric_version.prerelease?
        end

        def wants_date_based_version?
          return false unless dependency.numeric_version

          dependency.numeric_version >= version_class.new(100)
        end

        def matches_dependency_version_type?(comparison_version)
          return true unless dependency.version

          current_type = dependency.version
                                   .gsub("native-mt", "native_mt")
                                   .split(/[.\-]/)
                                   .find do |type|
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

        def version_class
          dependency.version_class
        end
      end
    end
  end
end
