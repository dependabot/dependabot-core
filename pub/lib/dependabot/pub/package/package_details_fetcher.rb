# typed: strict
# frozen_string_literal: true

require "json"
require "time"
require "cgi"
require "excon"
require "nokogiri"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/pub"
require "dependabot/package/package_release"
require "dependabot/package/package_details"
require "dependabot/pub/helpers"
require "dependabot/requirements_update_strategy"
require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/update_checkers/version_filters"

module Dependabot
  module Pub
    module Package
      class PackageDetailsFetcher
        extend T::Sig
        include Dependabot::Pub::Helpers

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { override.returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { override.returns(T::Hash[Symbol, T.untyped]) }
        attr_reader :options

        sig { override.returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            options: T::Hash[Symbol, T.untyped]
          )
            .void
        end
        def initialize(dependency:, dependency_files:, credentials:,
                       ignored_versions: [],
                       security_advisories: [], options: {})
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
          @ignored_versions = ignored_versions
          @security_advisories = security_advisories
          @options = options
        end

        sig { returns(T::Array[T::Hash[String, T.untyped]]) }
        def report
          @report ||= T.let(
            dependency_services_report,
            T.nilable(T::Array[T::Hash[String, T.untyped]])
          )
        end

        sig { returns(T.any(T::Array[Dependabot::Package::PackageRelease], T.untyped)) }
        def package_details_metadata
          package_releases = []
          T.let({}, T::Hash[String, T.untyped])

          Dependabot.logger.error("Initializing package metadata for \"#{@dependency.name}\"")

          response = fetch_package_metadata(dependency)
          return package_releases if response.status >= 500

          begin
            package_details_metadata = JSON.parse(response.body)

            package_details_metadata["versions"].select do |v|
              package_releases << package_release(version: v["version"],
                                                  publish_date: Time.parse(v["published"]))
            end

            package_releases
          rescue JSON::ParserError
            Dependabot.logger.error("Failed to parse package metadata")
            package_releases
          end
        rescue StandardError => e
          Dependabot.logger.error("Failed to fetch package metadata #{e.message}")
          package_releases
        end

        private

        sig do
          params(
            version: String,
            publish_date: T.nilable(Time)
          ).returns(Dependabot::Package::PackageRelease)
        end
        def package_release(version:, publish_date: nil)
          Dependabot::Package::PackageRelease.new(
            version: Pub::Version.new(version),
            released_at: publish_date
          )
        end
      end
    end
  end
end
