# typed: strict
# frozen_string_literal: true

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
          if all_versions.nil? || all_versions.empty?
            raise Dependabot::DependencyFileNotResolvable, "No versions found in manifests.txt"
          end

          Dependabot::Package::PackageDetails.new(
            dependency: dependency,
            releases: all_versions.map { |v| Dependabot::Package::PackageRelease.new(version: v) },
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
          response = Dependabot::RegistryClient.get(url: MANIFESTS_URL)
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
