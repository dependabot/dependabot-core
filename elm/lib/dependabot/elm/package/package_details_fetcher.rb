# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "cgi"
require "excon"
require "nokogiri"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/elm"
require "dependabot/elm/version"
require "dependabot/package/package_release"
require "dependabot/package/package_details"

module Dependabot
  module Elm
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

          @provider_url = T.let("https://package.elm-lang.org/packages/#{dependency.name}/releases.json",
                                T.nilable(String))
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T.nilable(T::Array[Dependabot::Package::PackageRelease])) }
        def fetch_package_releases
          releases = T.let([], T::Array[Dependabot::Package::PackageRelease])
          begin
            response = Dependabot::RegistryClient.get(
              url: T.must(@provider_url)
            )

            return [] unless response.status == 200

            package_metadata = JSON.parse(response.body)

            package_metadata.each do |version, release_date|
              releases << Dependabot::Package::PackageRelease.new(
                version: Elm::Version.new(version),
                released_at: release_date ? Time.at(release_date).to_time : nil
              )
            end

            releases
          rescue StandardError => e
            Dependabot.logger.error("Error while fetching package info for elm packages: #{e.message}")
            releases
          end
        end
      end
    end
  end
end
