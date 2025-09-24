# typed: strict
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

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            raise_on_ignored: T::Boolean,
            cooldown_options: T.nilable(Dependabot::Package::ReleaseCooldownOptions)
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          security_advisories:,
          raise_on_ignored: false,
          cooldown_options: nil
        )
          @security_advisories = security_advisories
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @raise_on_ignored    = raise_on_ignored
          @forbidden_urls      = T.let([], T::Array[T.untyped])
          @ignored_versions    = ignored_versions

          super(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            security_advisories: security_advisories,
            cooldown_options: cooldown_options,
            raise_on_ignored: raise_on_ignored,
            options: {}
          )
        end

        sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
        def latest_version_details
          possible_versions = package_release(versions)

          possible_versions = filter_prerelease_versions(possible_versions)
          possible_versions = filter_date_based_versions(possible_versions)
          possible_versions = filter_version_types(possible_versions)
          possible_versions = filter_ignored_versions(possible_versions)

          possible_versions = filter_cooldown_versions(possible_versions)

          return unless possible_versions.any?

          version_max = possible_versions.max_by(&:version)&.version

          url = possible_versions.select do |v| # rubocop:disable Performance/Detect
            v.version.to_s == version_max.to_s
          end.last&.url

          { version: version_max,
            source_url: url }
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          true
        end

        sig { returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
        def lowest_security_fix_version_details
          possible_versions = package_release(versions)

          possible_versions = filter_prerelease_versions(possible_versions)
          possible_versions = filter_date_based_versions(possible_versions)
          possible_versions = filter_version_types(possible_versions)
          possible_versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(
            possible_versions,
            security_advisories
          )
          possible_versions = filter_ignored_versions(possible_versions)
          possible_versions = filter_lower_versions(possible_versions)

          return unless possible_versions.any?

          version_min = possible_versions.min_by(&:version)&.version

          url = possible_versions.select do |v| # rubocop:disable Performance/Detect
            v.version.to_s == version_min.to_s
          end.last&.url

          { version: version_min,
            source_url: url }
        end

        sig { returns(T.any(T::Array[T::Hash[String, T.untyped]], T::Array[T::Hash[Symbol, T.untyped]])) }
        def versions
          Package::PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            forbidden_urls: forbidden_urls
          ).fetch_available_versions
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[T.untyped]) }
        attr_reader :dependency_files

        sig { returns(T::Array[T.untyped]) }
        attr_reader :credentials

        sig { returns(T.nilable(T::Array[String])) }
        attr_reader :forbidden_urls

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
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
            classifier = T.must(dependency.version).split(/[.\-]/).last
            Dependabot.logger.info("Filtered out #{diff} non-#{classifier} classifier versions")
          end
          filtered
        end

        sig { params(version: T::Array[T.untyped]).returns(T::Array[Dependabot::Package::PackageRelease]) }
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
          @package_details_fetcher ||= T.let(
            Package::PackageDetailsFetcher.new(
              dependency: dependency,
              dependency_files: dependency_files,
              credentials: credentials,
              forbidden_urls: []
            ),
            T.nilable(Dependabot::Gradle::Package::PackageDetailsFetcher)
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

        sig do
          params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def filter_cooldown_versions(releases)
          return releases unless cooldown_enabled?

          Dependabot.logger.info("Initializing cooldown filter")

          sorted_releases = releases.sort_by(&:version).reverse

          filtered_versions = []
          cooldown_filtered_versions = 0

          # Iterate through the sorted versions lazily, filtering out cooldown versions
          sorted_releases.each do |release|
            if in_cooldown_period?(release)
              Dependabot.logger.info("Filtered out (cooldown) : #{release}")
              cooldown_filtered_versions += 1

              next
            end

            filtered_versions << release
            break
          end

          Dependabot.logger.info("Filtered out #{cooldown_filtered_versions} version(s) due to cooldown")
          filtered_versions
        end

        sig { params(release: Dependabot::Package::PackageRelease).returns(T::Boolean) }
        def in_cooldown_period?(release)
          unless release.released_at
            Dependabot.logger.info("Release date not available for version #{release.version}")
            return false
          end

          current_version = version_class.correct?(dependency.version) ? version_class.new(dependency.version) : nil
          days = cooldown_days_for(current_version, release.version)

          # Calculate the number of seconds passed since the release
          passed_seconds = Time.now.to_i - release.released_at.to_i
          passed_days = passed_seconds / DAY_IN_SECONDS

          if passed_days < days
            Dependabot.logger.info(
              "Version #{release.version}, Release date: #{release.released_at}." \
              " Days since release: #{passed_days} (cooldown days: #{days})"
            )
          end

          # Check if the release is within the cooldown period
          passed_seconds < days * DAY_IN_SECONDS
        end

        sig { returns(T::Boolean) }
        def wants_prerelease?
          return false unless dependency.numeric_version

          T.must(dependency.numeric_version).prerelease?
        end

        sig { returns(T::Boolean) }
        def wants_date_based_version?
          return false unless dependency.numeric_version

          T.must(dependency.numeric_version) >= version_class.new(100)
        end

        sig { params(comparison_version: T.untyped).returns(T::Boolean) }
        def matches_dependency_version_type?(comparison_version)
          return true unless dependency.version

          current_type = T.must(dependency.version)
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

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end
        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details; end
      end
    end
  end
end
