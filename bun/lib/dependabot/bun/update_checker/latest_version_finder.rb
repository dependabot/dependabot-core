# typed: strict
# frozen_string_literal: true

require "excon"
require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/package/package_latest_version_finder"
require "dependabot/bun/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/bun/package/registry_finder"
require "dependabot/bun/package/package_details_fetcher"
require "dependabot/bun/version"
require "dependabot/bun/requirement"
require "sorbet-runtime"

module Dependabot
  module Bun
    class UpdateChecker
      class PackageLatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

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
          @package_fetcher = T.let(nil, T.nilable(Package::PackageDetailsFetcher))
          super
        end

        sig { returns(Package::PackageDetailsFetcher) }
        def package_fetcher
          return @package_fetcher if @package_fetcher

          @package_fetcher = Package::PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials
          )
          @package_fetcher
        end

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details
          return @package_details if @package_details

          @package_details = package_fetcher.fetch
          @package_details
        end

        sig do
          returns(T.nilable(Dependabot::Version))
        end
        def latest_version_from_registry
          fetch_latest_version(language_version: nil)
        end

        sig do
          override.params(language_version: T.nilable(T.any(String, Dependabot::Version)))
                  .returns(T.nilable(Dependabot::Version))
        end
        def latest_version_with_no_unlock(language_version: nil) # rubocop:disable Lint/UnusedMethodArgument
          with_custom_registry_rescue do
            return unless valid_npm_details?
            return version_from_dist_tags&.version if specified_dist_tag_requirement?

            releases = possible_releases
            in_range_versions = filter_out_of_range_versions(releases)
            in_range_versions.find { |r| !yanked_version?(r.version) }&.version
          end
        end

        sig do
          params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def lowest_security_fix_version(language_version: nil)
          fetch_lowest_security_fix_version(language_version: language_version)
        end

        # This method is for latest_version_from_registry
        sig do
          params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_latest_version(language_version: nil) # rubocop:disable Lint/UnusedMethodArgument
          with_custom_registry_rescue do
            return unless valid_npm_details?

            tag_release = version_from_dist_tags
            return tag_release.version if tag_release

            return if specified_dist_tag_requirement?

            possible_releases.find { |r| !yanked_version?(r.version) }&.version
          end
        end

        sig do
          override
            .params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_latest_version_with_no_unlock(language_version: nil) # rubocop:disable Lint/UnusedMethodArgument
          with_custom_registry_rescue do
            return unless valid_npm_details?
            return version_from_dist_tags&.version if specified_dist_tag_requirement?

            releases = possible_releases

            in_range_versions = filter_out_of_range_versions(releases)
            in_range_versions.find { |r| !yanked_version?(r.version) }&.version
          end
        end

        sig do
          override
            .params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_lowest_security_fix_version(language_version: nil) # rubocop:disable Lint/UnusedMethodArgument
          with_custom_registry_rescue do
            return unless valid_npm_details?

            secure_versions =
              if specified_dist_tag_requirement?
                [version_from_dist_tags].compact
              else
                possible_releases(filter_ignored: false)
              end

            secure_versions =
              Dependabot::UpdateCheckers::VersionFilters
              .filter_vulnerable_versions(
                T.unsafe(secure_versions),
                security_advisories
              )
            secure_versions = filter_ignored_versions(secure_versions)
            secure_versions = filter_lower_versions(secure_versions)

            # Find first non-yanked version
            secure_versions.sort_by(&:version).find do |version|
              !yanked_version?(version.version)
            end&.version
          end
        end

        sig do
          params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def filter_prerelease_versions(releases)
          releases.reject do |release|
            release.version.prerelease? && !related_to_current_pre?(release.version)
          end
        end

        sig do
          override.returns(T.nilable(T::Array[Dependabot::Package::PackageRelease]))
        end
        def available_versions
          possible_releases
        end

        sig do
          params(filter_ignored: T::Boolean)
            .returns(T::Array[T::Array[T.untyped]])
        end
        def possible_versions_with_details(filter_ignored: true)
          possible_releases(filter_ignored: filter_ignored).map { |r| [r.version, r.details] }
        end

        sig do
          params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def filter_releases(releases)
          filtered =
            releases
            .reject do |release|
              ignore_requirements.any? { |r| r.satisfied_by?(release.version) }
            end
          if @raise_on_ignored &&
             filter_lower_releases(filtered).empty? &&
             filter_lower_releases(releases).any?
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
        def filter_lower_releases(releases)
          return releases unless dependency.numeric_version

          releases.select { |release| release.version > dependency.numeric_version }
        end

        sig do
          params(filter_ignored: T::Boolean)
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def possible_releases(filter_ignored: true)
          releases = possible_previous_releases.reject do |r|
            r.details["deprecated"]
          end

          return filter_releases(releases) if filter_ignored

          releases
        end

        sig do
          params(filter_ignored: T::Boolean)
            .returns(T::Array[Gem::Version])
        end
        def possible_versions(filter_ignored: true)
          possible_releases(filter_ignored: filter_ignored).map(&:version)
        end

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def possible_previous_releases
          (package_details&.releases || [])
            .reject do |r|
            r.version.prerelease? && !related_to_current_pre?(T.unsafe(r.version))
          end
            .sort_by(&:version).reverse
        end

        sig { returns(T::Array[[Dependabot::Version, T::Hash[String, T.nilable(String)]]]) }
        def possible_previous_versions_with_details
          possible_previous_releases.map do |r|
            [r.version, r.details]
          end
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          true
        end

        private

        sig { params(_block: T.untyped).returns(T.nilable(Dependabot::Version)) }
        def with_custom_registry_rescue(&_block)
          yield
        rescue Excon::Error::Socket, Excon::Error::Timeout, RegistryError
          raise unless package_fetcher.custom_registry?

          # Custom registries can be flaky. We don't want to make that
          # our problem, so quietly return `nil` here.
          nil
        end

        sig { returns(T::Boolean) }
        def valid_npm_details?
          !!package_details&.releases&.any?
        end

        sig { returns(T.nilable(Dependabot::Package::PackageRelease)) }
        def version_from_dist_tags # rubocop:disable Metrics/PerceivedComplexity
          dist_tags = package_details&.dist_tags
          return nil unless dist_tags

          dist_tag_req = dependency.requirements
                                   .find { |r| dist_tags.include?(r[:requirement]) }
                                   &.fetch(:requirement)

          # For cooldown filtering, use filtered releases
          releases = available_versions

          releases = filter_by_cooldown(releases) if releases

          if dist_tag_req
            release = find_dist_tag_release(dist_tag_req, releases)
            return release unless release&.version && yanked_version?(release.version)
          end

          return nil unless dist_tags["latest"]

          latest_version = Version.new(dist_tags["latest"])

          if wants_latest_dist_tag?(latest_version)
            # Find the release object for this version, even if deprecated
            return possible_previous_releases.find { |r| r.version == latest_version }
          end

          nil
        end

        sig do
          params(
            dist_tag: T.nilable(String),
            releases: T.nilable(T::Array[Dependabot::Package::PackageRelease])
          )
            .returns(T.nilable(Dependabot::Package::PackageRelease))
        end
        def find_dist_tag_release(dist_tag, releases)
          dist_tags = package_details&.dist_tags
          return nil unless releases && dist_tags && dist_tag

          dist_tag_version = dist_tags[dist_tag]

          return nil unless dist_tag_version && !dist_tag_version.empty?

          release = releases.find { |r| r.version == Version.new(dist_tag_version) }

          release
        end

        sig { returns(T::Boolean) }
        def specified_dist_tag_requirement?
          dependency.requirements.any? do |req|
            next false if req[:requirement].nil?
            next false unless req[:requirement].match?(/^[A-Za-z]/)

            !req[:requirement].match?(/^v\d/i)
          end
        end

        sig do
          params(version: Dependabot::Version)
            .returns(T::Boolean)
        end
        def wants_latest_dist_tag?(version)
          return false if related_to_current_pre?(version) ^ version.prerelease?
          return false if current_version_greater_than?(version)
          return false if current_requirement_greater_than?(version)
          return false if ignore_requirements.any? { |r| r.satisfied_by?(version) }
          return false if yanked_version?(version)

          true
        end

        sig { params(version: Dependabot::Version).returns(T::Boolean) }
        def current_requirement_greater_than?(version)
          dependency.requirements.any? do |req|
            next false unless req[:requirement]

            req_version = req[:requirement].sub(/^\^|~|>=?/, "")
            next false unless version_class.correct?(req_version)

            version_class.new(req_version) > version
          end
        end

        sig { params(version: Dependabot::Version).returns(T::Boolean) }
        def related_to_current_pre?(version)
          current_version = dependency.numeric_version
          if current_version&.prerelease? &&
             current_version.release == version.release
            return true
          end

          dependency.requirements.any? do |req|
            next unless req[:requirement]&.match?(/\d-[A-Za-z]/)

            Bun::Requirement
              .requirements_array(req.fetch(:requirement))
              .any? do |r|
                r.requirements.any? { |a| a.last.release == version.release }
              end
          rescue Gem::Requirement::BadRequirementError
            false
          end
        end

        sig { params(version: Dependabot::Version).returns(T::Boolean) }
        def current_version_greater_than?(version)
          return false unless dependency.numeric_version

          T.must(dependency.numeric_version) > version
        end

        sig { params(version: Dependabot::Version).returns(T::Boolean) }
        def yanked_version?(version)
          package_fetcher.yanked?(version)
        end

        sig do
          params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def filter_out_of_range_versions(releases)
          reqs = dependency.requirements.filter_map do |r|
            Bun::Requirement.requirements_array(r.fetch(:requirement))
          end

          releases.select do |release|
            reqs.all? { |r| r.any? { |o| o.satisfied_by?(release.version) } }
          end
        end
      end
    end
  end
end
