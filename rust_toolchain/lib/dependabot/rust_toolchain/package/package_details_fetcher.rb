# typed: strong
# frozen_string_literal: true

require "date"
require "sorbet-runtime"
require "uri"

require "dependabot/package/package_details"
require "dependabot/registry_client"
require "dependabot/update_checkers/base"

require "dependabot/rust_toolchain"
require "dependabot/rust_toolchain/channel"
require "dependabot/rust_toolchain/channel_parser"
require "dependabot/rust_toolchain/version"

module Dependabot
  module RustToolchain
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        MANIFESTS_URL = "https://static.rust-lang.org/manifests.txt"
        MANIFEST_LINE = %r{static\.rust-lang\.org/dist/(\d{4}-\d{2}-\d{2})/channel-rust-(.+)\.toml}

        sig do
          params(
            dependency: Dependabot::Dependency
          ).void
        end
        def initialize(dependency:)
          @dependency = dependency
          @release_dates = T.let({}, T::Hash[String, Time])
        end

        sig { returns(Dependabot::Package::PackageDetails) }
        def fetch
          if all_versions.nil? || all_versions.empty?
            raise Dependabot::DependencyFileNotResolvable, "No versions found in manifests.txt"
          end

          Dependabot::Package::PackageDetails.new(
            dependency: dependency,
            releases: all_versions.map do |v|
              Dependabot::Package::PackageRelease.new(version: v, released_at: release_dates[v.to_s])
            end,
            dist_tags: nil
          )
        end

        private

        sig { returns(T::Array[Dependabot::RustToolchain::Version]) }
        def all_versions
          @all_versions ||= T.let(fetch_and_parse_manifests, T.nilable(T::Array[Dependabot::RustToolchain::Version]))
        end

        # Fetch the manifests.txt file and parse each line to extract version information
        sig { returns(T::Array[Dependabot::RustToolchain::Version]) }
        def fetch_and_parse_manifests
          # Cache bust by appending a timestamp query param so CDN treats each request uniquely
          # This avoids relying on headers that might be ignored by intermediate caches.
          busted_url = "#{MANIFESTS_URL}?t=#{Time.now.to_i}"
          response = Dependabot::RegistryClient.get(url: busted_url)
          manifests_content = response.body

          channels = T.let([], T::Array[Dependabot::RustToolchain::Version])

          manifests_content.each_line do |line|
            line = line.strip
            next if line.empty?

            channel = parse_manifest_line(line)
            channels << channel if channel
          end

          channels.uniq
        end

        sig { params(line: String).returns(T.nilable(Dependabot::RustToolchain::Version)) }
        def parse_manifest_line(line)
          match = line.match(MANIFEST_LINE)
          return nil unless match

          date = T.must(match[1])
          channel_part = T.must(match[2])

          version = version_for(channel_part, date)
          record_release_date(version, date) if version
          version
        end

        sig { params(channel_part: String, date: String).returns(T.nilable(Dependabot::RustToolchain::Version)) }
        def version_for(channel_part, date)
          case channel_part
          when STABLE_CHANNEL
            Version.new("#{STABLE_CHANNEL}-#{date}")
          when BETA_CHANNEL
            Version.new("#{BETA_CHANNEL}-#{date}")
          when NIGHTLY_CHANNEL
            Version.new("#{NIGHTLY_CHANNEL}-#{date}")
          when /^\d+\.\d+(\.\d+)?$/
            Version.new(channel_part)
          end
        end

        # The manifest's dist date is the day that toolchain was published, which is what
        # `cooldown` needs. A version can appear in more than one manifest; keep the earliest.
        sig { params(version: Dependabot::RustToolchain::Version, date: String).void }
        def record_release_date(version, date)
          day = Date.strptime(date, "%Y-%m-%d")
          released_at = Time.utc(day.year, day.month, day.day)
          key = version.to_s
          existing = release_dates[key]
          release_dates[key] = released_at if existing.nil? || released_at < existing
        rescue Date::Error
          nil
        end

        sig { returns(T::Hash[String, Time]) }
        attr_reader :release_dates

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency
      end
    end
  end
end
