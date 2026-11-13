# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/update_checkers/base"
require "dependabot/package/package_latest_version_finder"

require "dependabot/vcpkg/package/package_details_fetcher"
require "dependabot/vcpkg/requirement"
require "dependabot/vcpkg/version"

module Dependabot
  module Vcpkg
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details
          @package_details ||= T.let(
            Package::PackageDetailsFetcher.new(dependency: dependency).fetch,
            T.nilable(Dependabot::Package::PackageDetails)
          )
        end

        sig do
          override
            .params(language_version: T.nilable(T.any(String, Dependabot::Version)))
            .returns(T.nilable(Dependabot::Version))
        end
        def fetch_latest_version(language_version: nil) # rubocop:disable Lint/UnusedMethodArgument
          latest_release_info&.version
        end

        sig { returns(T.nilable(Dependabot::Package::PackageRelease)) }
        def latest_release_info
          @latest_release_info ||= T.let(
            begin
              releases = available_versions
              return unless releases

              releases = filter_yanked_versions(releases)
              releases = filter_by_cooldown(releases)
              releases = filter_ignored_versions(releases)

              releases.max_by(&:version)
            end,
            T.nilable(Dependabot::Package::PackageRelease)
          )
        end

        # vcpkg refuses to compare versions whose schemes differ, so a release it could never
        # select is not a candidate. Filtering here rather than in a later hook keeps every
        # inherited comparison operating on a mutually comparable set. Registry baselines are
        # exempt: they are release tags rather than port versions.
        sig { returns(T.nilable(T::Array[Dependabot::Package::PackageRelease])) }
        def available_versions
          releases = super
          return releases if registry_dependency?

          current = current_version
          return releases unless releases && current

          current_scheme = declared_scheme(releases, current)
          releases.select do |release|
            version = release.version
            version.is_a?(Dependabot::Vcpkg::Version) &&
              Dependabot::Vcpkg::Version.comparable?(version, scheme_of(release), current, current_scheme)
          end
        end

        # The release tag for the given commit SHA, if any.
        sig { params(commit_sha: String).returns(T.nilable(String)) }
        def tag_for_commit_sha(commit_sha)
          package_details
            &.releases
            &.find { |release| T.cast(release.details["commit_sha"], T.nilable(String)) == commit_sha }
            &.tag
        end

        private

        # The scheme the registry published the currently selected version under.
        sig do
          params(
            releases: T::Array[Dependabot::Package::PackageRelease],
            current: Dependabot::Vcpkg::Version
          ).returns(T.nilable(String))
        end
        def declared_scheme(releases, current)
          scheme_of(releases.find { |release| release.version.eql?(current) })
        end

        sig { params(release: T.nilable(Dependabot::Package::PackageRelease)).returns(T.nilable(String)) }
        def scheme_of(release)
          scheme = T.cast(release&.details&.dig("scheme"), T.nilable(Object))
          scheme.is_a?(String) ? scheme : nil
        end

        sig { returns(T.nilable(Dependabot::Vcpkg::Version)) }
        def current_version
          return @current_version if @looked_up_current_version

          @looked_up_current_version = T.let(true, T.nilable(T::Boolean))
          version = dependency.version
          @current_version = T.let(
            version && Dependabot::Vcpkg::Version.correct?(version) ? Dependabot::Vcpkg::Version.new(version) : nil,
            T.nilable(Dependabot::Vcpkg::Version)
          )
        end

        sig { returns(T::Boolean) }
        def registry_dependency?
          dependency.source_details(allowed_types: ["git"]) in { type: "git" }
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled? = true
      end
    end
  end
end
