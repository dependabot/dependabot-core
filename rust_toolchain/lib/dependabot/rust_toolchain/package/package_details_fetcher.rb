# typed: strong
# frozen_string_literal: true

require "base64"
require "sorbet-runtime"
require "uri"

require "dependabot/credential"
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
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency:, credentials: [])
          @dependency = dependency
          @credentials = T.let(credentials, T::Array[Dependabot::Credential])
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
          # Cache bust by appending a timestamp query param so CDN treats each request uniquely
          # This avoids relying on headers that might be ignored by intermediate caches.
          busted_url = "#{manifests_url}?t=#{Time.now.to_i}"
          response = Dependabot::RegistryClient.get(url: busted_url, headers: auth_headers)
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

        sig { returns(String) }
        def manifests_url
          replaces_base = @credentials.find do |cred|
            cred["type"] == "rust_registry" && cred.replaces_base?
          end
          return MANIFESTS_URL unless replaces_base

          url = replaces_base["url"]
          return MANIFESTS_URL unless url

          url.chomp("/") + "/manifests.txt"
        end

        sig { returns(T::Hash[String, String]) }
        def auth_headers
          replaces_base = @credentials.find do |cred|
            cred["type"] == "rust_registry" && cred.replaces_base?
          end
          return {} unless replaces_base

          token = replaces_base["token"]
          return { "Authorization" => "Bearer #{token}" } if token

          username = replaces_base["username"]
          password = replaces_base["password"]
          if username && password
            encoded = Base64.strict_encode64("#{username}:#{password}")
            return { "Authorization" => "Basic #{encoded}" }
          end

          {}
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency
      end
    end
  end
end
