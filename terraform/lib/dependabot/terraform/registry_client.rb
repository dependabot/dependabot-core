# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/registry_client"
require "dependabot/source"
require "dependabot/terraform/version"
require "dependabot/terraform/private_registry_logger"

module Dependabot
  module Terraform
    # Terraform::RegistryClient is a basic API client to interact with a
    # terraform registry: https://www.terraform.io/docs/registry/api.html
    class RegistryClient
      extend T::Sig

      # Archive extensions supported by Terraform for HTTP URLs
      # https://developer.hashicorp.com/terraform/language/modules/sources#http-urls
      ARCHIVE_EXTENSIONS = T.let(
        %w(.zip .bz2 .tar.bz2 .tar.tbz2 .tbz2 .gz .tar.gz .tgz .xz .tar.xz .txz).freeze,
        T::Array[String]
      )
      PUBLIC_HOSTNAME = "registry.terraform.io"

      sig { params(hostname: String, credentials: T::Array[Dependabot::Credential]).void }
      def initialize(hostname: PUBLIC_HOSTNAME, credentials: [])
        @hostname = hostname
        @tokens = T.let(
          credentials.each_with_object({}) do |item, memo|
            memo[item["host"]] = item["token"] if item["type"] == "terraform_registry"
          end,
          T::Hash[String, String]
        )
      end

      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/CyclomaticComplexity
      # See https://www.terraform.io/docs/modules/sources.html#http-urls for
      # details of how Terraform handle HTTP(S) sources for modules
      sig { params(raw_source: String).returns(String) }
      def self.get_proxied_source(raw_source)
        return raw_source unless raw_source.start_with?("http")

        uri = URI.parse(T.must(raw_source.split(%r{(?<!:)//}).first))
        return raw_source if ARCHIVE_EXTENSIONS.any? { |ext| uri.path&.end_with?(ext) }
        return raw_source if URI.parse(raw_source).query&.include?("archive=")

        url = T.must(raw_source.split(%r{(?<!:)//}).first) + "?terraform-get=1"
        host = URI.parse(raw_source).host

        response = Dependabot::RegistryClient.get(url: url)
        raise PrivateSourceAuthenticationFailure, host if response.status == 401

        return T.must(response.headers["X-Terraform-Get"]) if response.headers["X-Terraform-Get"]

        doc = Nokogiri::XML(response.body)
        doc.css("meta").find do |tag|
          tag.attributes&.fetch("name", nil)&.value == "terraform-get"
        end&.attributes&.fetch("content", nil)&.value
      rescue Excon::Error::Socket, Excon::Error::Timeout => e
        raise PrivateSourceAuthenticationFailure, host if e.message.include?("no address for")

        raw_source
      end
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/PerceivedComplexity

      # Fetch all the versions of a provider, and return a Version
      # representation of them.
      #
      # @param identifier [String] the identifier for the dependency, i.e:
      # "hashicorp/aws"
      # @return [Array<Dependabot::Terraform::Version>]
      # @raise [Dependabot::DependabotError] when the versions cannot be retrieved
      sig { params(identifier: String).returns(T::Array[Dependabot::Terraform::Version]) }
      def all_provider_versions(identifier:)
        base_url = service_url_for("providers.v1")
        response = http_get!(URI.join(base_url, "#{identifier}/versions"))

        JSON.parse(response.body)
            .fetch("versions")
            .map { |release| version_class.new(release.fetch("version")) }
      rescue Excon::Error
        raise error("Could not fetch provider versions")
      end

      # Fetch all the versions of a module, and return a Version
      # representation of them.
      #
      # @param identifier [String] the identifier for the dependency, i.e:
      # "hashicorp/consul/aws"
      # @return [Array<Dependabot::Terraform::Version>]
      # @raise [Dependabot::DependabotError] when the versions cannot be retrieved
      sig { params(identifier: String).returns(T::Array[Dependabot::Terraform::Version]) }
      def all_module_versions(identifier:)
        base_url = service_url_for("modules.v1")
        response = http_get!(URI.join(base_url, "#{identifier}/versions"))

        JSON.parse(response.body)
            .fetch("modules").first.fetch("versions")
            .map { |release| version_class.new(release.fetch("version")) }
      end

      # Fetch the "source" for a module or provider. We use the API to fetch
      # the source for a dependency, this typically points to a source code
      # repository, and then instantiate a Dependabot::Source object that we
      # can use to fetch Metadata about a specific version of the dependency.
      #
      # @param dependency [Dependabot::Dependency] the dependency who's source
      # we're attempting to find
      # @return [nil, Dependabot::Source]
      sig { params(dependency: Dependabot::Dependency).returns(T.nilable(Dependabot::Source)) }
      def source(dependency:)
        type = T.must(dependency.requirements.first)[:source][:type]

        PrivateRegistryLogger.log_registry_operation(
          hostname: hostname,
          operation: "source_resolution",
          details: {
            dependency_name: dependency.name,
            dependency_version: dependency.version,
            source_type: type
          }
        )

        base_url = service_url_for(service_key_for(type))
        source_url = nil

        case type
        # https://www.terraform.io/internals/module-registry-protocol#download-source-code-for-a-specific-module-version
        when "module", "modules", "registry"
          source_url = resolve_module_source(dependency, base_url)
        when "provider", "providers"
          source_url = resolve_provider_source(dependency, base_url)
        end

        result = Source.from_url(source_url) if source_url

        PrivateRegistryLogger.log_registry_operation(
          hostname: hostname,
          operation: "source_resolution_success",
          details: {
            dependency_name: dependency.name,
            resolved_source_url: source_url,
            has_source: !result.nil?
          }
        )

        result
      rescue JSON::ParserError, Excon::Error::Timeout => e
        PrivateRegistryLogger.log_registry_error(
          hostname: hostname,
          error: e,
          context: {
            operation: "source_resolution",
            dependency_name: dependency.name,
            dependency_version: dependency.version
          }
        )
        nil
      rescue StandardError => e
        PrivateRegistryLogger.log_registry_error(
          hostname: hostname,
          error: e,
          context: {
            operation: "source_resolution",
            dependency_name: dependency.name,
            dependency_version: dependency.version
          }
        )
        raise
      end

      # Perform service discovery and return the absolute URL for
      # the requested service.
      # https://www.terraform.io/docs/internals/remote-service-discovery.html
      #
      # @param service_key [String] the service type described in https://www.terraform.io/docs/internals/remote-service-discovery.html#supported-services
      # @param return String
      # @raise [Dependabot::PrivateSourceAuthenticationFailure] when the service is not available
      sig { params(service_key: String).returns(String) }
      def service_url_for(service_key)
        url_for(services.fetch(service_key))
      rescue KeyError
        raise Dependabot::PrivateSourceAuthenticationFailure, "Host does not support required Terraform-native service"
      end

      private

      sig { returns(String) }
      attr_reader :hostname

      sig { returns(T::Hash[String, String]) }
      attr_reader :tokens

      sig { returns(T.class_of(Dependabot::Terraform::Version)) }
      def version_class
        Version
      end

      sig { params(hostname: String).returns(T::Hash[String, String]) }
      def headers_for(hostname)
        token = tokens[hostname]
        headers = token ? { "Authorization" => "Bearer #{token}" } : {}

        # Add enhanced headers for private registries
        if PrivateRegistryLogger.private_registry?(hostname)
          headers.merge!(enhanced_headers_for_private_registry(hostname))
        end

        headers
      end

      # Provides enhanced headers specifically for private registry requests.
      #
      # This method adds additional headers that improve compatibility and debugging
      # for private registry interactions, such as a descriptive User-Agent header.
      # It also logs authentication context for debugging purposes.
      #
      # @param hostname [String] The hostname of the private registry
      # @return [Hash<String, String>] Additional headers for private registry requests
      sig { params(hostname: String).returns(T::Hash[String, String]) }
      def enhanced_headers_for_private_registry(hostname)
        # Add User-Agent for better debugging and registry compatibility
        enhanced_headers = {
          "User-Agent" => "Dependabot-Terraform/#{Dependabot::VERSION}"
        }

        # Log authentication context for debugging
        has_token = !tokens[hostname].nil?
        PrivateRegistryLogger.log_registry_operation(
          hostname: hostname,
          operation: "authentication_setup",
          details: {
            has_token: has_token,
            token_length: has_token ? tokens[hostname].length : 0
          }
        )

        enhanced_headers
      end

      # Validates that appropriate credentials are available for a given hostname.
      #
      # For private registries, this method checks if authentication tokens are available.
      # For public registries, it always returns true as no authentication is required.
      # The validation result is logged for debugging purposes.
      #
      # @param hostname [String] The hostname to validate credentials for
      # @return [Boolean] true if credentials are available or not required, false otherwise
      sig { params(hostname: String).returns(T::Boolean) }
      def validate_credentials_for_hostname(hostname)
        return true unless PrivateRegistryLogger.private_registry?(hostname)

        has_credentials = !tokens[hostname].nil?

        PrivateRegistryLogger.log_registry_operation(
          hostname: hostname,
          operation: "credential_validation",
          details: { has_credentials: has_credentials }
        )

        has_credentials
      end

      sig { returns(T::Hash[String, String]) }
      def services
        @services ||= T.let(
          begin
            response = http_get(url_for("/.well-known/terraform.json"))
            response.status == 200 ? JSON.parse(response.body) : {}
          end,
          T.nilable(T::Hash[String, String])
        )
      end

      sig { params(type: String).returns(String) }
      def service_key_for(type)
        case type
        when "module", "modules", "registry"
          "modules.v1"
        when "provider", "providers"
          "providers.v1"
        else
          raise error("Invalid source type")
        end
      end

      sig { params(url: T.any(String, URI::Generic)).returns(Excon::Response) }
      def http_get(url)
        Dependabot::RegistryClient.get(
          url: url.to_s,
          headers: headers_for(hostname)
        )
      rescue Excon::Error::Socket, Excon::Error::Timeout
        raise PrivateSourceBadResponse, hostname
      end

      sig { params(url: URI::Generic).returns(Excon::Response) }
      def http_get!(url)
        response = http_get(url)

        if response.status == 401
          PrivateRegistryLogger.log_registry_error(
            hostname: hostname,
            error: StandardError.new("Authentication failed"),
            context: {
              operation: "http_request",
              url: url.to_s,
              status: response.status,
              has_credentials: validate_credentials_for_hostname(hostname)
            }
          )
          raise Dependabot::PrivateSourceAuthenticationFailure, hostname
        end

        unless response.status == 200
          error_msg = "Response from registry was #{response.status}"
          PrivateRegistryLogger.log_registry_error(
            hostname: hostname,
            error: StandardError.new(error_msg),
            context: {
              operation: "http_request",
              url: url.to_s,
              status: response.status
            }
          )
          raise error(error_msg)
        end

        response
      end

      sig { params(path: String).returns(String) }
      def url_for(path)
        uri = URI.parse(path)
        return uri.to_s if uri.scheme == "https"
        raise error("Unsupported scheme provided") if uri.host && uri.scheme

        uri.host = hostname
        uri.scheme = "https"
        uri.to_s
      end

      sig { params(message: String).returns(Dependabot::DependabotError) }
      def error(message)
        Dependabot::DependabotError.new(message)
      end

      sig { params(dependency: Dependabot::Dependency, base_url: String).returns(T.nilable(String)) }
      def resolve_module_source(dependency, base_url)
        download_url = URI.join(base_url, "#{dependency.name}/#{dependency.version}/download")
        response = http_get(download_url)

        if response.status == 401
          raise Dependabot::PrivateSourceAuthenticationFailure, hostname
        end

        return nil unless response.status == 204

        source_url = response.headers.fetch("X-Terraform-Get")
        source_url = URI.join(download_url, source_url) if
          source_url.start_with?("/", "./", "../")
        source_url = RegistryClient.get_proxied_source(source_url) if source_url
        source_url
      end

      sig { params(dependency: Dependabot::Dependency, base_url: String).returns(T.nilable(String)) }
      def resolve_provider_source(dependency, base_url)
        response = http_get(URI.join(base_url, "#{dependency.name}/#{dependency.version}"))
        return nil unless response.status == 200

        JSON.parse(response.body).fetch("source")
      end
    end
  end
end
