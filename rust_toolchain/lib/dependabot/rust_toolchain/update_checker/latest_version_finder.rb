# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/update_checkers/base"
require "dependabot/package/package_latest_version_finder"

require "dependabot/rust_toolchain/channel_type"
require "dependabot/rust_toolchain/package/package_details_fetcher"
require "dependabot/rust_toolchain/version"

module Dependabot
  module RustToolchain
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
        extend T::Sig

        sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
        def package_details
          @package_details ||= Dependabot::RustToolchain::Package::PackageDetailsFetcher.new(
            dependency: dependency
          ).fetch
        end

        protected

        sig do
          override
            .params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def apply_post_fetch_latest_versions_filter(releases)
          filter_by_version_type(releases)
        end

        sig do
          override
            .params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def apply_post_fetch_lowest_security_fix_versions_filter(releases)
          filter_by_version_type(releases)
        end

        sig { override.returns(T::Boolean) }
        def cooldown_enabled?
          Dependabot::Experiments.enabled?(:enable_cooldown_for_rust_toolchain)
        end

        private

        sig do
          params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def filter_by_version_type(releases)
          current_version = T.cast(dependency.numeric_version, T.nilable(Dependabot::RustToolchain::Version))
          return [] unless current_version

          current_channel = current_version.channel
          return [] unless current_channel

          current_type = current_channel.channel_type

          # There are no updates for channels
          # i.e. "stable", "beta", "nightly"
          return [] if current_type == ChannelType::Stability

          is_current_major_minor = major_minor_format?(current_version.to_s)

          channel_matched_releases = releases.filter_map do |release|
            release_rust_version = T.cast(release.version, Dependabot::RustToolchain::Version)
            release_channel = release_rust_version.channel
            next unless release_channel

            # Check that the release version is in the same channel type
            next unless release_channel.channel_type == current_type

            next release unless release_channel.channel_type == ChannelType::Version

            # For version channels, we need to ensure that the version format matches
            is_release_major_minor = major_minor_format?(release_rust_version.to_s)
            case [is_current_major_minor, is_release_major_minor]
            in [true, true] | [false, false]
              release
            else
              nil
            end
          end

          channel_matched_releases.uniq do |release|
            release.version.to_s
          end
        end

        # Check if a version string is in major.minor format (e.g., "1.72" vs "1.72.0")
        sig { params(version_string: String).returns(T::Boolean) }
        def major_minor_format?(version_string)
          version_string.count(".") == 1
        end
      end
    end
  end
end
