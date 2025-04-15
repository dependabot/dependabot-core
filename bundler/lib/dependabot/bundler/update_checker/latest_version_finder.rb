# typed: strict
# frozen_string_literal: true

require "excon"

require "dependabot/bundler/update_checker"
require "dependabot/update_checkers/version_filters"
require "dependabot/bundler/requirement"
require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/package/package_latest_version_finder"
require "dependabot/bundler/update_checker/latest_version_finder/" \
        "dependency_source"
require "dependabot/bundler/package/package_details_fetcher"
require "sorbet-runtime"

module Dependabot
  module Bundler
    class UpdateChecker
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            cooldown_options: T.nilable(Dependabot::Package::ReleaseCooldownOptions),
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
          @package_details = T.let(nil, T.nilable(Dependabot::Package::PackageDetails))
          @latest_version_details = T.let(nil, T.nilable(T::Hash[Symbol, T.untyped]))
          super
        end

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details
          @package_details ||= Package::PackageDetailsFetcher.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials
          ).fetch
        end

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def latest_version_details
          @latest_version_details ||= if cooldown_enabled?
                                        latest_version = fetch_latest_version(language_version: nil)
                                        latest_version ? { version: latest_version } : nil
                                      else
                                        fetch_latest_version_details
                                      end
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          Dependabot::Experiments.enabled?(:enable_cooldown_for_bundler)
        end

        sig { override.returns(T.nilable(T::Array[Dependabot::Package::PackageRelease])) }
        def available_versions
          return nil if package_details&.releases.nil?

          source_versions = dependency_source.versions
          return [] if source_versions.empty?

          T.must(package_details).releases.select do |release|
            source_versions.any? { |v| v.to_s == release.version.to_s }
          end
        end

        private

        sig { returns(T.nilable(T::Hash[Symbol, Dependabot::Version])) }
        def fetch_latest_version_details
          return dependency_source.latest_git_version_details if dependency_source.git?

          relevant_versions = available_versions || []
          relevant_versions = filter_prerelease_versions(relevant_versions)
          relevant_versions = filter_ignored_versions(relevant_versions)

          return if relevant_versions.empty?

          release = relevant_versions.max_by(&:version)

          return if release.nil?

          { version: release.version }
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def fetch_lowest_security_fix_version
          return if dependency_source.git?

          relevant_versions = available_versions || []
          relevant_versions = filter_prerelease_versions(relevant_versions)
          relevant_versions = Dependabot::UpdateCheckers::VersionFilters
                              .filter_vulnerable_versions(
                                relevant_versions,
                                security_advisories
                              )
          relevant_versions = filter_ignored_versions(relevant_versions)
          relevant_versions = filter_lower_versions(relevant_versions)

          relevant_versions.min_by(&:version)&.version
        end

        sig { returns(T::Boolean) }
        def wants_prerelease?
          @wants_prerelease ||= T.let(
            begin
              current_version = dependency.numeric_version
              if current_version&.prerelease?
                true
              else
                dependency.requirements.any? do |req|
                  req[:requirement].match?(/[a-z]/i)
                end
              end
            end, T.nilable(T::Boolean)
          )
        end

        sig { returns(DependencySource) }
        def dependency_source
          @dependency_source ||= T.let(
            DependencySource.new(
              dependency: dependency,
              dependency_files: dependency_files,
              credentials: credentials,
              options: options
            ), T.nilable(DependencySource)
          )
        end
      end
    end
  end
end
