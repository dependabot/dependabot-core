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

        sig do
          params(
            dependency: Dependabot::Dependency,
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency:, credentials:)
          @dependency = dependency
          @credentials = credentials
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def fetch_package_releases
          releases = T.let([], T::Array[Dependabot::Package::PackageRelease])
          
          begin
            registry_client = RegistryClient.new(credentials: credentials)
            uuid = T.cast(dependency.metadata[:julia_uuid], T.nilable(String))
            
            # Fetch all available versions
            available_versions = registry_client.fetch_available_versions(dependency.name, uuid)
            return releases if available_versions.empty?

            available_versions.each do |version_string|
              version = Julia::Version.new(version_string)
              
              # Fetch release date for this version
              release_date = registry_client.fetch_version_release_date(dependency.name, version_string, uuid)
              
              releases << Dependabot::Package::PackageRelease.new(
                version: version,
                released_at: release_date,
                latest: false, # Will be determined later
                yanked: false, # Julia registries don't support yanked packages
                language: Dependabot::Package::PackageLanguage.new(name: PACKAGE_LANGUAGE)
              )
            rescue StandardError => e
              Dependabot.logger.warn("Failed to fetch release info for #{dependency.name} version #{version_string}: #{e.message}")
              # Create release without date if we can't fetch it
              releases << Dependabot::Package::PackageRelease.new(
                version: version,
                released_at: nil,
                latest: false,
                yanked: false,
                language: Dependabot::Package::PackageLanguage.new(name: PACKAGE_LANGUAGE)
              )
            end

            # Mark the latest version
            unless releases.empty?
              latest_release = releases.max_by(&:version)
              latest_release.instance_variable_set(:@latest, true) if latest_release
            end

            releases
          rescue StandardError => e
            Dependabot.logger.error("Error while fetching package releases for #{dependency.name}: #{e.message}")
            releases
          end
        end
      end
    end
  end
end
