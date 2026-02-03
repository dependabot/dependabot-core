# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "dependabot/registry_client"
require "dependabot/python/name_normaliser"
require "dependabot/python/version"

module Dependabot
  module PreCommit
    module Package
      # Fetches package details from PyPI for Python additional_dependencies.
      # This is a simplified version that reuses Python ecosystem's version handling.
      class PypiPackageDetailsFetcher
        extend T::Sig

        PYPI_JSON_API = T.let("https://pypi.org/pypi", String)

        sig do
          params(
            package_name: String,
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(package_name:, credentials:)
          @package_name = package_name
          @credentials = credentials
        end

        sig { returns(String) }
        attr_reader :package_name

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        # Fetches the latest version from PyPI
        sig { returns(T.nilable(String)) }
        def latest_version
          response = fetch_from_pypi
          return nil unless response

          version_string = response.dig("info", "version")
          return nil unless version_string.is_a?(String)
          return nil unless Dependabot::Python::Version.correct?(version_string)

          version_string
        end

        # Fetches all available versions from PyPI
        sig { returns(T::Array[String]) }
        def available_versions
          response = fetch_from_pypi
          return [] unless response

          releases = response["releases"]
          return [] unless releases.is_a?(Hash)

          valid_versions = releases.keys.select do |version_string|
            Dependabot::Python::Version.correct?(version_string)
          end

          valid_versions
            .sort_by { |version_string| Dependabot::Python::Version.new(version_string) }
            .reverse
        end

        private

        sig { returns(T.nilable(T::Hash[String, T.untyped])) }
        def fetch_from_pypi
          normalised_name = Dependabot::Python::NameNormaliser.normalise(package_name)
          url = "#{PYPI_JSON_API}/#{normalised_name}/json"

          response = Dependabot::RegistryClient.get(
            url: url,
            headers: { "Accept" => "application/json" }
          )

          return nil unless response.status == 200

          JSON.parse(response.body)
        rescue JSON::ParserError, Excon::Error::Timeout, Excon::Error::Socket => e
          Dependabot.logger.warn("Failed to fetch PyPI data for #{package_name}: #{e.message}")
          nil
        end
      end
    end
  end
end
