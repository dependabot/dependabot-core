# typed: strict
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
require "dependabot/github_actions/file_parser"
require "dependabot/github_actions/package/package_details_fetcher"
require "dependabot/github_actions/requirement"
require "dependabot/github_actions/update_checker"

module Dependabot
  module GithubActions
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
        sig { returns(T::Boolean) }
        attr_reader :raise_on_ignored

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details; end

        sig { returns(T.nilable(T.any(Dependabot::Version, String))) }
        def latest_release
          available_releases
        end

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def lowest_security_fix_release
          available_security_fix_releases
        end

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def latest_version_tag
          available_latest_version_tag
        end

        private

        sig { returns(T.nilable(Dependabot::GitHubActions::Package::PackageDetailsFetcher)) }
        def package_details_fetcher
          @package_details_fetcher = T.let(Dependabot::GitHubActions::Package::PackageDetailsFetcher
            .new(
              dependency: dependency,
              credentials: credentials,
              ignored_versions: ignored_versions,
              raise_on_ignored: raise_on_ignored,
              security_advisories: security_advisories
            ), T.nilable(Dependabot::GitHubActions::Package::PackageDetailsFetcher))
        end

        sig { returns(T.nilable(T.any(Dependabot::Version, String))) }
        def available_releases
          # # TODO: Support Docker sources
          # return unless git_dependency?

          @available_releases = T.let(package_details_fetcher.release_list_for_git_dependency,
                                      T.nilable(T.any(Dependabot::Version, String)))
        end

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def available_security_fix_releases
          # # TODO: Support Docker sources
          # return unless git_dependency?

          @available_security_fix_releases = T.let(package_details_fetcher.lowest_security_fix_version_tag,
                                                   T.nilable(T::Hash[Symbol, T.untyped]))
        end

        sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
        def available_latest_version_tag
          @latest_version_tag = T.let(package_details_fetcher.latest_version_tag,
                                      T.nilable(T::Hash[Symbol, T.untyped]))
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          Dependabot::Experiments.enabled?(:enable_cooldown_for_github_actions)
        end
      end
    end
  end
end
