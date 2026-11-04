# typed: strong
# frozen_string_literal: true

require "time"
require "dependabot/julia/registry_client"
require "dependabot/julia/version"
require "dependabot/package/package_release"
require "dependabot/package/package_language"

module Dependabot
  module Julia
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        PACKAGE_LANGUAGE = "julia"
        RELEASE_DATE_PENDING = "release_date_pending"

        sig do
          params(
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential],
            custom_registries: T::Array[T::Hash[Symbol, String]]
          ).void
        end
        def initialize(dependency:, credentials:, custom_registries: [])
          @dependency = dependency
          @credentials = credentials
          @custom_registries = custom_registries
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[T::Hash[Symbol, String]]) }
        attr_reader :custom_registries

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def fetch_package_releases
          registry_client = RegistryClient.new(
            credentials: credentials,
            custom_registries: custom_registries
          )
          uuid = T.cast(dependency.metadata[:julia_uuid], T.nilable(String))

          # Fetch all available versions. Domain errors (package not found)
          # come back as an empty list; infrastructure failures raise and are
          # classified by the updater's error handler rather than being
          # silently treated as "no update available".
          available_versions = registry_client.fetch_available_versions(dependency.name, uuid)
          return [] if available_versions.empty?

          releases = build_releases_for_versions(registry_client, available_versions, uuid)
          mark_latest_release(releases)

          releases
        end

        private

        sig do
          params(
            registry_client: RegistryClient,
            available_versions: T::Array[String],
            uuid: T.nilable(String)
          ).returns(T::Array[Dependabot::Package::PackageRelease])
        end
        def build_releases_for_versions(registry_client, available_versions, uuid)
          # Use batch operation to fetch all release dates at once
          release_dates = fetch_release_dates_batch(registry_client, available_versions, uuid)

          available_versions.map do |version_string|
            version = Julia::Version.new(version_string)
            date_result = release_dates[version_string]
            date_result = nil if date_result.is_a?(RegistryClient::Result::Failure)

            create_package_release(
              version,
              convert_single_date(date_result&.release_date),
              release_date_pending: date_result&.pending || false
            )
          end
        end

        sig do
          params(
            registry_client: RegistryClient,
            available_versions: T::Array[String],
            uuid: T.nilable(String)
          ).returns(
            T::Hash[String, T.any(RegistryClient::Result::ReleaseDate, RegistryClient::Result::Failure)]
          )
        end
        def fetch_release_dates_batch(registry_client, available_versions, uuid)
          return {} if available_versions.empty?

          packages_versions = [
            RegistryClient::Result::PackageVersionsRequest.new(
              name: dependency.name,
              uuid: uuid || "",
              versions: available_versions
            )
          ]

          result = registry_client.batch_fetch_version_release_dates(packages_versions)
          return {} if result.is_a?(RegistryClient::Result::Failure)

          dates_for_package = result.packages[dependency.name]
          return {} unless dates_for_package.is_a?(RegistryClient::Result::ReleaseDates)

          dates_for_package.dates
        end

        sig { params(date_value: T.nilable(String)).returns(T.nilable(Time)) }
        def convert_single_date(date_value)
          return nil if date_value.nil?

          Time.parse(date_value)
        rescue ArgumentError, TypeError
          nil
        end

        sig do
          params(
            version: Julia::Version,
            release_date: T.nilable(Time),
            release_date_pending: T::Boolean
          ).returns(Dependabot::Package::PackageRelease)
        end
        def create_package_release(version, release_date, release_date_pending:)
          Dependabot::Package::PackageRelease.new(
            version: version,
            released_at: release_date,
            latest: false, # Will be determined later
            yanked: false, # Yanked versions are filtered out by the Julia registry helper
            language: Dependabot::Package::PackageLanguage.new(name: PACKAGE_LANGUAGE),
            details: release_date_pending ? { RELEASE_DATE_PENDING => true } : {}
          )
        end

        sig { params(releases: T::Array[Dependabot::Package::PackageRelease]).void }
        def mark_latest_release(releases)
          return if releases.empty?

          latest_release = releases.max_by(&:version)
          latest_release&.instance_variable_set(:@latest, true)
        end
      end
    end
  end
end
