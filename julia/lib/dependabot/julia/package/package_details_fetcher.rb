# typed: strict
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
          releases = T.let([], T::Array[Dependabot::Package::PackageRelease])

          begin
            registry_client = RegistryClient.new(
              credentials: credentials,
              custom_registries: custom_registries
            )
            uuid = T.cast(dependency.metadata[:julia_uuid], T.nilable(String))

            # Fetch all available versions
            available_versions = registry_client.fetch_available_versions(dependency.name, uuid)
            return releases if available_versions.empty?

            releases = build_releases_for_versions(registry_client, available_versions, uuid)
            mark_latest_release(releases)

            releases
          rescue StandardError => e
            Dependabot.logger.error("Error while fetching package releases for #{dependency.name}: #{e.message}")
            releases
          end
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
            release_date = release_dates[version_string]

            create_package_release(version, release_date)
          end
        end

        sig do
          params(
            registry_client: RegistryClient,
            available_versions: T::Array[String],
            uuid: T.nilable(String)
          ).returns(T::Hash[String, T.nilable(Time)])
        end
        def fetch_release_dates_batch(registry_client, available_versions, uuid)
          return {} if available_versions.empty?

          packages_versions = [{
            name: dependency.name,
            uuid: uuid || "",
            versions: available_versions
          }]

          result = registry_client.batch_fetch_version_release_dates(packages_versions)
          dates_for_package = result[dependency.name] || {}

          convert_dates_to_time_objects(dates_for_package)
        end

        sig do
          params(
            dates_hash: T::Hash[String, T.untyped]
          ).returns(T::Hash[String, T.nilable(Time)])
        end
        def convert_dates_to_time_objects(dates_hash)
          dates_hash.transform_values do |date_value|
            convert_single_date(date_value)
          end
        end

        sig { params(date_value: T.untyped).returns(T.nilable(Time)) }
        def convert_single_date(date_value)
          return nil if date_value.nil?
          return nil if date_value.is_a?(Hash) && date_value["error"]

          Time.parse(date_value.to_s)
        rescue ArgumentError, TypeError
          nil
        end

        sig do
          params(
            version: Julia::Version,
            release_date: T.nilable(Time)
          ).returns(Dependabot::Package::PackageRelease)
        end
        def create_package_release(version, release_date)
          Dependabot::Package::PackageRelease.new(
            version: version,
            released_at: release_date,
            latest: false, # Will be determined later
            yanked: false, # Julia registries don't support yanked packages
            language: Dependabot::Package::PackageLanguage.new(name: PACKAGE_LANGUAGE)
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
