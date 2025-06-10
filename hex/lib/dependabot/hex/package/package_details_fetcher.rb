# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "cgi"
require "excon"
require "nokogiri"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/hex"
require "dependabot/hex/version"
require "dependabot/package/package_release"
require "dependabot/package/package_details"

module Dependabot
  module Hex
    module Package
      class PackageDetailsFetcher
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency
          ).void
        end
        def initialize(dependency:)
          @dependency = dependency

          @dependency_url = T.let("https://hex.pm/api/packages/#{dependency.name}", T.nilable(String))
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T.nilable(T::Array[Dependabot::Package::PackageRelease])) }
        def fetch_package_releases
          releases = T.let([], T::Array[Dependabot::Package::PackageRelease])

          begin
            Dependabot.logger.info("Fetching package (hex) info for #{@dependency.name}")

            response = Dependabot::RegistryClient.get(url: T.must(@dependency_url))
            return releases unless response.status == 200

            package_metadata = JSON.parse(response.body)&.fetch("releases", []) || []
            package_metadata.each do |release|
              releases << Dependabot::Package::PackageRelease.new(
                version: Hex::Version.new(release["version"]),
                released_at: release["inserted_at"] ? Time.new(release["inserted_at"]) : nil,
                url: release["url"]
              )
            end

            releases
          rescue StandardError => e
            Dependabot.logger.error("Error while fetching package info for hex packages: #{e.message}")
            releases
          end
        end
      end
    end
  end
end
