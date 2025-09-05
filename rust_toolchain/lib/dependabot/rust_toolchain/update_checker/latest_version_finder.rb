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
        def cooldown_enabled? = true

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

          return [] if stability_channel_without_updates?(current_channel)

          is_current_major_minor = major_minor_format?(current_version.to_s)

          channel_matched_releases = releases.select do |release|
            compatible_release?(release, current_channel, is_current_major_minor)
          end

          channel_matched_releases.uniq do |release|
            release.version.to_s
          end
        end

        sig { params(channel: T.untyped).returns(T::Boolean) }
        def stability_channel_without_updates?(channel)
          channel.channel_type == ChannelType::Stability
        end

        sig do
          params(
            release: Dependabot::Package::PackageRelease,
            current_channel: T.untyped,
            is_current_major_minor: T::Boolean
          )
            .returns(T::Boolean)
        end
        def compatible_release?(release, current_channel, is_current_major_minor)
          release_rust_version = T.cast(release.version, Dependabot::RustToolchain::Version)
          release_channel = release_rust_version.channel
          return false unless release_channel

          return false unless matching_channel_type?(release_channel, current_channel)
          return false unless matching_dated_stability?(release_channel, current_channel)
          return true unless version_channel?(release_channel)

          matching_version_format?(release_rust_version, is_current_major_minor)
        end

        sig { params(release_channel: T.untyped, current_channel: T.untyped).returns(T::Boolean) }
        def matching_channel_type?(release_channel, current_channel)
          release_channel.channel_type == current_channel.channel_type
        end

        sig { params(release_channel: T.untyped, current_channel: T.untyped).returns(T::Boolean) }
        def matching_dated_stability?(release_channel, current_channel)
          return true unless current_channel.channel_type == ChannelType::DatedStability

          release_channel.stability == current_channel.stability
        end

        sig { params(channel: T.untyped).returns(T::Boolean) }
        def version_channel?(channel)
          channel.channel_type == ChannelType::Version
        end

        sig do
          params(
            release_version: Dependabot::RustToolchain::Version,
            is_current_major_minor: T::Boolean
          )
            .returns(T::Boolean)
        end
        def matching_version_format?(release_version, is_current_major_minor)
          is_release_major_minor = major_minor_format?(release_version.to_s)
          is_current_major_minor == is_release_major_minor
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
