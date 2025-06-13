# typed: strong
# frozen_string_literal: true

require "dependabot/julia/registry_client"
require "dependabot/julia/version"
require "dependabot/update_checkers/version_filters"

module Dependabot
  module Julia
    class LatestVersionFinder
      extend T::Sig

      sig do
        params(
          dependency: Dependabot::Dependency,
          dependency_files: T::Array[Dependabot::DependencyFile],
          credentials: T::Array[Dependabot::Credential],
          ignored_versions: T::Array[String],
          security_advisories: T::Array[Dependabot::SecurityAdvisory],
          raise_on_ignored: T::Boolean
        ).void
      end
      def initialize(dependency:, dependency_files:, credentials:, ignored_versions:, security_advisories:,
                     raise_on_ignored:)
        @dependency = dependency
        @dependency_files = dependency_files
        @credentials = credentials
        @ignored_versions = ignored_versions
        @security_advisories = security_advisories
        @raise_on_ignored = raise_on_ignored
      end

      sig { returns(T.nilable(Gem::Version)) }
      def latest_version
        @latest_version ||= T.let(fetch_latest_version, T.nilable(Gem::Version))
      end

      private

      sig { returns(Dependabot::Dependency) }
      attr_reader :dependency

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      attr_reader :dependency_files

      sig { returns(T::Array[Dependabot::Credential]) }
      attr_reader :credentials

      sig { returns(T::Array[String]) }
      attr_reader :ignored_versions

      sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
      attr_reader :security_advisories

      sig { returns(T::Boolean) }
      attr_reader :raise_on_ignored

      sig { returns(T.nilable(Gem::Version)) }
      def fetch_latest_version
        # Use the main registry client (has DependabotHelper.jl with built-in fallback)
        registry_client = RegistryClient.new(credentials: credentials)
        uuid = T.cast(dependency.metadata[:julia_uuid], T.nilable(String))
        latest_version = registry_client.fetch_latest_version(dependency.name, uuid)

        return nil unless latest_version

        # Filter out ignored versions
        versions = [latest_version]

        # Filter out ignored versions manually
        versions = versions.reject do |version|
          ignored_versions.any?(version.to_s)
        end

        # Filter out vulnerable versions
        filtered_versions = Dependabot::UpdateCheckers::VersionFilters.filter_vulnerable_versions(
          versions,
          security_advisories
        )

        raise Dependabot::AllVersionsIgnored if filtered_versions.empty? && raise_on_ignored

        filtered_versions.max
      end
    end
  end
end
