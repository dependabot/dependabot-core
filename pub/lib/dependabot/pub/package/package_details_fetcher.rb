# typed: strong
# frozen_string_literal: true

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

        sig { override.returns(T::Hash[Symbol, T.anything]) }
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
            options: T::Hash[Symbol, T.anything]
          )
            .void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions: [],
          security_advisories: [],
          options: {}
        )
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
          @ignored_versions = ignored_versions
          @security_advisories = security_advisories
          @options = options
        end

        sig { returns(T::Array[DependencyServicesResult::ReportEntry]) }
        def report
          @report ||= T.let(
            dependency_services_report,
            T.nilable(T::Array[DependencyServicesResult::ReportEntry])
          )
        end

        sig { returns(T::Array[Dependabot::Package::PackageRelease]) }
        def package_details_metadata
          Dependabot.logger.info("Initializing package metadata for \"#{@dependency.name}\"")

          response = fetch_package_metadata(dependency)
          return [] if response.status >= 500

          # Build the full list up front. If any release can't be parsed (e.g. a
          # missing or invalid publish date) the partial result is discarded, so
          # callers can treat a non-empty list as a complete, trustworthy snapshot
          # and an empty list as "no usable metadata".
          RegistryPackage.from_json(response.body).releases
        rescue JsonValueParser::InvalidValue
          Dependabot.logger.error("Failed to parse package metadata")
          []
        rescue StandardError => e
          Dependabot.logger.error("Failed to fetch package metadata #{e.message}")
          []
        end
      end
    end
  end
end
