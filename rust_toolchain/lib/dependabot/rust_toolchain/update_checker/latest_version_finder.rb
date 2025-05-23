# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module RustToolchain
    class LatestVersionFinder < Dependabot::Package::PackageLatestVersionFinder
      extend T::Sig

      sig { override.returns(T.nilable(Dependabot::Package::PackageDetails)) }
      def package_details
        @package_details ||= Dependabot::RustToolchain::Package::PackageDetailsFetcher.new(
          dependency: dependency
        ).fetch
      end

      protected

      # Override to add type-based filtering specific to Rust toolchain
      sig do
        override
          .params(releases: T::Array[Dependabot::Package::PackageRelease])
          .returns(T::Array[Dependabot::Package::PackageRelease])
      end
      def apply_post_fetch_latest_versions_filter(releases)
        filter_by_version_type(releases)
      end

      # Override to add type-based filtering for security fixes
      sig do
        params(releases: T::Array[Dependabot::Package::PackageRelease])
          .returns(T::Array[Dependabot::Package::PackageRelease])
      end
      def apply_post_fetch_lowest_security_fix_versions_filter(releases)
        filter_by_version_type(releases)
      end

      private

      # Filter releases to only include versions of the same type as the current dependency
      sig do
        params(releases: T::Array[Dependabot::Package::PackageRelease])
          .returns(T::Array[Dependabot::Package::PackageRelease])
      end
      def filter_by_version_type(releases)
        current_version = dependency.version
        return releases unless current_version

        current_rust_version = Dependabot::RustToolchain::Version.new(current_version)
        current_channel = T.cast(current_rust_version.instance_variable_get(:@channel),
                                 T.nilable(Dependabot::RustToolchain::Channel))
        return releases unless current_channel

        current_type = current_channel.channel_type

        filtered = releases.select do |release|
          release_rust_version = T.cast(release.version, Dependabot::RustToolchain::Version)
          release_channel = T.cast(release_rust_version.instance_variable_get(:@channel),
                                   T.nilable(Dependabot::RustToolchain::Channel))
          next false unless release_channel

          case current_type
          when :version
            # For versions, ensure same channel type and compatible version format
            next false unless release_channel.channel_type == :version

            # If current version has major.minor format, new version should not have patch
            current_version_str = current_channel.version
            if current_version_str && is_major_minor_format?(current_version_str)
              release_version_str = release_channel.version
              release_version_str ? is_major_minor_format?(release_version_str) : false
            else
              true
            end
          when :dated_channel
            # For dated channels, must be same channel type and same channel name
            release_channel.channel_type == :dated_channel &&
              release_channel.channel == current_channel.channel
          when :channel
            # For simple channels, must be same channel type and same channel name
            release_channel.channel_type == :channel &&
              release_channel.channel == current_channel.channel
          else
            false
          end
        end

        if releases.count > filtered.count
          Dependabot.logger.info("Filtered out #{releases.count - filtered.count} incompatible version types")
        end

        filtered
      end

      # Check if a version string is in major.minor format (e.g., "1.72" vs "1.72.0")
      sig { params(version_string: String).returns(T::Boolean) }
      def is_major_minor_format?(version_string)
        parts = version_string.split(".")
        parts.length == 2
      end
    end
  end
end
