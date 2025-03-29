# typed: true
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/registry_client"
require "dependabot/source"
require "dependabot/terraform/version"
require "json"
require "uri"

module Dependabot
  module Terraform
    class ReleasesClient
      RELEASES_API_URL = "https://releases.hashicorp.com/terraform/index.json"

      # Fetch all Terraform versions from the release API.
      #
      # @return [Array<Dependabot::Terraform::Version>]
      # @raise [Dependabot::DependabotError] if versions cannot be fetched
      def all_terraform_versions
        response = http_get!(RELEASES_API_URL)
        parse_versions(response.body)
      rescue JSON::ParserError, KeyError => e
        raise error("Failed to parse Terraform versions: #{e.message}")
      rescue Excon::Error => e
        raise error("Could not fetch Terraform versions: #{e.message}")
      end

      private

      # Perform an HTTP GET request with error handling.
      #
      # @param url [String] The URL to fetch
      # @return [Excon::Response]
      # @raise [Dependabot::DependabotError] for HTTP errors
      def http_get!(url)
        response = http_get(url)

        raise Dependabot::PrivateSourceAuthenticationFailure, hostname if response.status == 401
        raise error("Unexpected response: #{response.status}") unless response.status == 200

        response
      end

      # Perform an HTTP GET request.
      #
      # @param url [String] The URL to fetch
      # @return [Excon::Response]
      def http_get(url)
        Dependabot::RegistryClient.get(url: url.to_s)
      end

      # Parse the version data from the API response.
      #
      # @param body [String] The response body
      # @return [Array<Dependabot::Terraform::Version>]
      def parse_versions(body)
        JSON.parse(body)
            .fetch("versions", [])
            .map { |release| version_class.new(release.fetch("version")) }
      end

      # Retrieve the class for handling version instances.
      #
      # @return [Class] The version class
      def version_class
        Dependabot::Terraform::Version
      end

      # Generate a standardized error object.
      #
      # @param message [String] The error message
      # @return [Dependabot::DependabotError]
      def error(message)
        Dependabot::DependabotError.new(message)
      end
    end
  end
end
