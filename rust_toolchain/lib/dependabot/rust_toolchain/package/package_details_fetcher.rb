# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "time"
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

        sig do
          params(
            dependency: Dependabot::Dependency
          ).void
        end
        def initialize(dependency:)
          @dependency = dependency
        end

        sig { returns(Dependabot::Package::PackageDetails) }
        def fetch
          if all_releases.nil? || all_releases.empty?
            raise Dependabot::DependencyFileNotResolvable, "No versions found in manifests.txt"
          end

          Dependabot::Package::PackageDetails.new(
            dependency: dependency,
            releases: all_releases,
            dist_tags: nil
          )
        end

        private

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def all_releases
          @all_releases ||= T.let(
            fetch_and_parse_manifests,
            T.nilable(T::Array[Dependabot::Package::PackageRelease])
          )
        end

        # Fetch the manifests.txt file and parse each line to extract release information
        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def fetch_and_parse_manifests
          # Cache bust by appending a timestamp query param so CDN treats each request uniquely
          # This avoids relying on headers that might be ignored by intermediate caches.
          busted_url = "#{MANIFESTS_URL}?t=#{Time.now.to_i}"
          response = Dependabot::RegistryClient.get(url: busted_url)
          manifests_content = response.body

          releases = T.let([], T::Array[Dependabot::Package::PackageRelease])

          manifests_content.each_line do |line|
            line = line.strip
            next if line.empty?

            version = parse_manifest_line(line)
            next unless version

            releases << Dependabot::Package::PackageRelease.new(
              version: version,
              released_at: manifest_release_date(line)
            )
          end

          releases.uniq(&:version)
        end

        sig { params(line: String).returns(Time) }
        def manifest_release_date(line)
          date = T.must(line.match(%r{/dist/(\d{4}-\d{2}-\d{2})/}))[1]
          Time.iso8601("#{date}T00:00:00Z")
        end

        sig { params(line: String).returns(T.nilable(Dependabot::RustToolchain::Version)) }
        def parse_manifest_line(line)
          match = line.match(%r{static\.rust-lang\.org/dist/(\d{4}-\d{2}-\d{2})/channel-rust-(.+)\.toml})
          return nil unless match

          date = match[1]
          channel_part = match[2]

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

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency
      end
    end
  end
end
