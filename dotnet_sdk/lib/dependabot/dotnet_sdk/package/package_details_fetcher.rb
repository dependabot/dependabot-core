# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/package/package_details"

require "dependabot/dotnet_sdk/version"

module Dependabot
  module DotnetSdk
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        RELEASES_INDEX_URL = "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/releases-index.json"

        sig do
          params(
            dependency: Dependabot::Dependency
          ).void
        end
        def initialize(dependency:)
          @dependency = dependency
          @package_details = T.let(nil, T.nilable(Dependabot::Package::PackageDetails))
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig do
          returns(T.nilable(Dependabot::Package::PackageDetails))
        end
        def fetch
          package_releases = releases.filter_map do |release|
            version = release["version"]
            release_date = release["release-date"]
            next unless version && release_date

            package_release(
              version: version,
              released_at: Time.parse(release_date)
            )
          end

          package_details(package_releases)
        end

        private

        sig { returns(T::Array[T::Hash[String, String]]) }
        def releases
          response = releases_response
          return [] unless response.status == 200

          parsed = JSON.parse(response.body)
          parsed["releases-index"].flat_map do |release|
            release_channel(release["releases.json"])
          end
        end

        sig { returns(Excon::Response) }
        def releases_response
          Dependabot::RegistryClient.get(
            url: RELEASES_INDEX_URL,
            headers: { "Accept" => "application/json" }
          )
        end

        sig { params(url: String).returns(T::Array[T::Hash[String, String]]) }
        def release_channel(url)
          response = release_channel_response(url)
          return [] unless response

          JSON.parse(response.body)
              .fetch("releases", [])
              .flat_map { |release| extract_release_versions(release) }
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotResolvable, "Invalid JSON response from #{url}"
        end

        sig { params(release: T::Hash[String, T.untyped]).returns(T::Array[T::Hash[String, String]]) }
        def extract_release_versions(release)
          release_date = release["release-date"]
          return [] unless release_date

          if release["sdks"].nil?
            sdk_version = release.dig("sdk", "version")
            return [] unless sdk_version

            [{ "version" => sdk_version, "release-date" => release_date }]
          else
            release["sdks"]&.filter_map do |sdk|
              next unless sdk["version"]

              { "version" => sdk["version"], "release-date" => release_date }
            end || []
          end
        end

        sig { params(url: String).returns(T.nilable(Excon::Response)) }
        def release_channel_response(url)
          Dependabot::RegistryClient.get(
            url: url,
            headers: { "Accept" => "application/json" }
          )
        end

        sig do
          params(
            version: String,
            released_at: T.nilable(Time)
          ).returns(Dependabot::Package::PackageRelease)
        end
        def package_release(version:, released_at:)
          Dependabot::Package::PackageRelease.new(
            version: DotnetSdk::Version.new(version),
            released_at: released_at
          )
        end

        sig do
          params(releases: T::Array[Dependabot::Package::PackageRelease])
            .returns(Dependabot::Package::PackageDetails)
        end
        def package_details(releases)
          @package_details ||= Dependabot::Package::PackageDetails.new(
            dependency: dependency,
            releases: releases.reverse.uniq(&:version)
          )
        end
      end
    end
  end
end
