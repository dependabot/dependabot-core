# typed: strong
# frozen_string_literal: true

require "excon"
require "json"
require "sorbet-runtime"

require "open3"
require "shellwords"
require "dependabot/errors"
require "dependabot/package/package_latest_version_finder"
require "dependabot/shared_helpers"
require "dependabot/update_checkers/version_filters"
require "dependabot/devcontainers/file_parser"
require "dependabot/devcontainers/package/package_details_fetcher"
require "dependabot/devcontainers/requirement"
require "dependabot/devcontainers/update_checker"

module Dependabot
  module Devcontainers
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
            raise_on_ignored: T::Boolean,
            options: T::Hash[Symbol, T.untyped],
            cooldown_options: T.nilable(Dependabot::Package::ReleaseCooldownOptions)
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          security_advisories:,
          raise_on_ignored:,
          options: {},
          cooldown_options: nil
        )
          @dependency          = dependency
          @dependency_files    = dependency_files
          @credentials         = credentials
          @ignored_versions    = ignored_versions
          @security_advisories = security_advisories
          @raise_on_ignored    = raise_on_ignored
          @options             = options
          @cooldown_options = cooldown_options
          super
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency
        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials
        sig { returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions)) }
        attr_reader :cooldown_options
        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions
        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories
        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details; end

        sig { returns(T.nilable(T::Array[Dependabot::Version])) }
        def release_versions
          releases = package_releases

          releases = filter_ignored_versions(T.must(releases))
          releases = filter_lower_versions(releases)
          releases = filter_by_cooldown(releases)

          return Array(current_version) if releases.empty?

          releases.map(&:version)
        end

        private

        sig { returns(T.nilable(T::Array[Dependabot::Package::PackageRelease])) }
        def package_releases
          @package_releases = T.let(Dependabot::Devcontainers::Package::PackageDetailsFetcher
            .new(dependency: dependency)
            .fetch_package_releases, T.nilable(T::Array[Dependabot::Package::PackageRelease]))
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          Dependabot::Experiments.enabled?(:enable_cooldown_for_devcontainers)
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def current_version
          @current_version ||=
            T.let(
              dependency.numeric_version,
              T.nilable(Dependabot::Version)
            )
        end
      end
    end
  end
end
