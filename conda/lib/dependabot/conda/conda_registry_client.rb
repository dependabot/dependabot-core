# typed: strict
# frozen_string_literal: true

require "excon"
require "json"
require "sorbet-runtime"
require "dependabot/conda/version"
require "dependabot/registry_client"
require "dependabot/shared_helpers"

module Dependabot
  module Conda
    class CondaRegistryClient
      extend T::Sig

      # Supported public conda channels (user-facing names from environment.yml)
      SUPPORTED_CHANNELS = T.let(
        %w(anaconda conda-forge defaults bioconda main).freeze,
        T::Array[String]
      )

      # Channel aliases: maps user-facing channel names to API channel names
      # 'defaults' is a Conda client alias that doesn't exist on anaconda.org API
      CHANNEL_ALIASES = T.let(
        { "defaults" => "anaconda" }.freeze,
        T::Hash[String, String]
      )
      # anaconda.org API configuration
      DEFAULT_CHANNEL = T.let("anaconda", String)
      API_BASE_URL = T.let("https://api.anaconda.org", String)
      CONNECTION_TIMEOUT = T.let(5, Integer)
      READ_TIMEOUT = T.let(10, Integer)
      MAX_RETRIES = T.let(1, Integer)

      sig { void }
      def initialize
        @cache = T.let({}, T::Hash[String, T.untyped])
        @not_found_cache = T.let(Set.new, T::Set[String])
      end

      # Fetch package metadata from Conda API
      sig do
        params(
          package_name: String,
          channel: String
        ).returns(T.nilable(T::Hash[String, T.untyped]))
      end
      def fetch_package_metadata(package_name, channel = DEFAULT_CHANNEL)
        cache_key = "#{channel}/#{package_name}"

        # Check 404 cache first
        return nil if @not_found_cache.include?(cache_key)

        # Check cache
        return @cache[cache_key] if @cache.key?(cache_key)

        # Fetch from API
        fetch_from_api(package_name, channel, cache_key)
      end

      # Check if a specific version exists for a package
      sig do
        params(
          package_name: String,
          version: String,
          channel: String
        ).returns(T::Boolean)
      end
      def version_exists?(package_name, version, channel = DEFAULT_CHANNEL)
        metadata = fetch_package_metadata(package_name, channel)
        return false unless metadata

        versions = metadata["versions"]
        return false unless versions.is_a?(Array)

        versions.include?(version)
      end

      # Get all available versions for a package, sorted newest first
      sig do
        params(
          package_name: String,
          channel: String
        ).returns(T::Array[Dependabot::Conda::Version])
      end
      def available_versions(package_name, channel = DEFAULT_CHANNEL)
        metadata = fetch_package_metadata(package_name, channel)
        return [] unless metadata

        versions = metadata["versions"]
        return [] unless versions.is_a?(Array)

        # Parse and sort versions
        parsed_versions = versions.filter_map do |version_string|
          Dependabot::Conda::Version.new(version_string)
        rescue ArgumentError
          # Invalid version format - skip it
          Dependabot.logger.debug("Skipping invalid conda version: #{version_string}")
          nil
        end

        # Sort newest first
        parsed_versions.sort.reverse
      end

      # Get the latest version for a package
      sig do
        params(
          package_name: String,
          channel: String
        ).returns(T.nilable(Dependabot::Conda::Version))
      end
      def latest_version(package_name, channel = DEFAULT_CHANNEL)
        versions = available_versions(package_name, channel)
        versions.first
      end

      # Get package metadata fields for MetadataFinder
      sig do
        params(
          package_name: String,
          channel: String
        ).returns(T.nilable(T::Hash[Symbol, T.nilable(String)]))
      end
      def package_metadata(package_name, channel = DEFAULT_CHANNEL)
        metadata = fetch_package_metadata(package_name, channel)
        return nil unless metadata

        {
          homepage: metadata["home"],
          source_url: metadata["dev_url"],
          description: metadata["summary"],
          license: metadata["license"]
        }
      end

      private

      # Normalize channel name from user-facing to API-compatible
      sig { params(channel: String).returns(String) }
      def normalize_channel(channel)
        CHANNEL_ALIASES[channel] || channel
      end

      sig do
        params(
          package_name: String,
          channel: String,
          cache_key: String
        ).returns(T.nilable(T::Hash[String, T.untyped]))
      end
      def fetch_from_api(package_name, channel, cache_key)
        # Normalize channel name for API (e.g., 'defaults' -> 'anaconda')
        api_channel = normalize_channel(channel)
        url = "#{API_BASE_URL}/package/#{api_channel}/#{package_name}"

        begin
          response = make_http_request(url)
          handle_response(response, package_name, cache_key)
        rescue JSON::ParserError => e
          Dependabot.logger.error("Invalid JSON from Conda API for #{package_name}: #{e.message}")
          nil
        rescue Excon::Error::Socket, Excon::Error::Timeout => e
          Dependabot.logger.error("Conda API connection error for #{package_name}: #{e.message}")
          raise Dependabot::DependabotError, "Failed to connect to Conda API: #{e.message}"
        end
      end

      sig { params(url: String).returns(Excon::Response) }
      def make_http_request(url)
        Dependabot::RegistryClient.get(
          url: url,
          headers: {
            "Accept" => "application/json",
            "User-Agent" => Dependabot::SharedHelpers::USER_AGENT
          },
          options: {
            connect_timeout: CONNECTION_TIMEOUT,
            read_timeout: READ_TIMEOUT,
            retry_limit: MAX_RETRIES
          }
        )
      end

      sig do
        params(
          response: Excon::Response,
          package_name: String,
          cache_key: String
        ).returns(T.nilable(T::Hash[String, T.untyped]))
      end
      def handle_response(response, package_name, cache_key)
        case response.status
        when 200
          data = JSON.parse(response.body)
          @cache[cache_key] = data
          data
        when 404
          @not_found_cache.add(cache_key)
          nil
        when 429
          handle_rate_limit(response, package_name)
        else
          Dependabot.logger.error("Unexpected Conda API response: #{response.status} for #{package_name}")
          nil
        end
      end

      sig { params(response: Excon::Response, package_name: String).returns(T.noreturn) }
      def handle_rate_limit(response, package_name)
        retry_after = response.headers["Retry-After"]&.to_i || 60
        Dependabot.logger.warn(
          "Conda API rate limited. Retry after #{retry_after} seconds. Package: #{package_name}"
        )
        raise Dependabot::DependabotError,
              "Conda API rate limited. Please try again in #{retry_after} seconds."
      end
    end
  end
end
