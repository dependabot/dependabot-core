# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/registry_client"
require "dependabot/source"
require "dependabot/terraform/version"

module Dependabot
  module Terraform
    # Terraform::RegistryClient is a basic API client to interact with a
    # terraform registry: https://developer.hashicorp.com/terraform/registry/api-docs
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
        source_url = fetch_source_url(dependency, type)

        return nil unless source_url

        parse_source_url(source_url, dependency, type)
      rescue JSON::ParserError, Excon::Error::Timeout
        nil
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

      # Fetch source URL from registry API. The source can be a module or a
      # provider, both using different endpoints and response formats.
      #
      # @param dependency [Dependabot::Dependency] the dependency to fetch the
      # source for
      # @param type [String] the type of the dependency, normally either
      # "module" or "provider"
      # @return [String, nil] the source URL or nil if not found
      sig { params(dependency: Dependabot::Dependency, type: String).returns(T.nilable(String)) }
      def fetch_source_url(dependency, type)
        base_url = service_url_for(service_key_for(type))
        case type
        when "module", "modules", "registry"
          fetch_module_source_url(dependency, base_url)
        when "provider", "providers"
          fetch_provider_source_url(dependency, base_url)
        end
      end

      # Fetch the source URL of a given module dependency.
      #
      # See:
      # - https://www.terraform.io/internals/module-registry-protocol#download-source-code-for-a-specific-module-version
      #
      # @param dependency [Dependabot::Dependency] the module dependency
      # @param base_url [String] the base URL for the module registry service
      # @return [String, nil] the source URL or nil if not found
      sig { params(dependency: Dependabot::Dependency, base_url: String).returns(T.nilable(String)) }
      def fetch_module_source_url(dependency, base_url)
        # Example: https://registry.terraform.io/v1/modules/hashicorp/consul/aws/0.3.8/download
        download_url = URI.join(base_url, "#{dependency.name}/#{dependency.version}/download")
        response = http_get(download_url)
        return nil unless response.status == 204

        source_url = response.headers["X-Terraform-Get"]
        return nil unless source_url

        source_url = URI.join(download_url, source_url) if
          source_url.start_with?("/", "./", "../")
        RegistryClient.get_proxied_source(source_url.to_s) if source_url
      end

      # Fetch the source URL of a given provider dependency.
      #
      # See:
      # - https://developer.hashicorp.com/terraform/internals/provider-registry-protocol#find-a-provider-package
      #
      # @param dependency [Dependabot::Dependency] the provider dependency
      # @param base_url [String] the base URL for the provider registry service
      # @return [String, nil] the source URL or nil if not found
      sig { params(dependency: Dependabot::Dependency, base_url: String).returns(T.nilable(String)) }
      def fetch_provider_source_url(dependency, base_url)
        # Example: https://registry.terraform.io/v1/providers/hashicorp/aws/3.40.0
        response = http_get(URI.join(base_url, "#{dependency.name}/#{dependency.version}"))
        return nil unless response.status == 200

        JSON.parse(response.body).fetch("source")
      end

      # Parse source URL into Dependabot::Source object with fallback for archivist URLs.
      # When download endpoints return unparseable archivist URLs (encrypted blob storage),
      # falls back to the module metadata API to get the actual repository URL.
      #
      # See:
      # - https://developer.hashicorp.com/terraform/internals/module-registry-protocol#download-source-code-for-a-specific-module-version
      # - https://developer.hashicorp.com/terraform/cloud-docs/architectural-details/security-model (archivist URLs)
      #
      # @param source_url [String] the source URL to parse (may be archivist URL)
      # @param dependency [Dependabot::Dependency] the dependency for fallback metadata lookup
      # @param type [String] the type of the dependency ("module", "provider", "registry")
      # @return [Dependabot::Source, nil] the parsed source or nil if not found
      sig do
        params(
          source_url: String,
          dependency: Dependabot::Dependency,
          type: String
        ).returns(T.nilable(Dependabot::Source))
      end
      def parse_source_url(source_url, dependency, type)
        result = Source.from_url(source_url)

        # If Source.from_url fails (e.g., with archivist URLs), try to get source from module metadata
        result = source_from_module_metadata(dependency) if result.nil? && type == "registry"

        result
      end

      # Fallback to fetch source repository URL from module metadata API.
      # Used when X-Terraform-Get header returns unparseable archivist URLs like:
      # https://archivist.terraform.io/v1/object/dmF1bHQ6djE6... (encrypted blob storage)
      #
      # The metadata API returns JSON with the actual repository URL in the "source" field.
      #
      # See: https://developer.hashicorp.com/terraform/registry/api-docs#show-a-module
      #
      # @param dependency [Dependabot::Dependency] the dependency to fetch metadata for
      # @return [Dependabot::Source, nil] the parsed source or nil if not found
      sig { params(dependency: Dependabot::Dependency).returns(T.nilable(Dependabot::Source)) }
      def source_from_module_metadata(dependency)
        base_url = service_url_for("modules.v1")
        metadata_url = URI.join(base_url, dependency.name.to_s)

        response = http_get(metadata_url)
        return nil unless response.status == 200

        data = JSON.parse(response.body)
        source_url = data["source"]

        Source.from_url(source_url) if source_url
      rescue JSON::ParserError, Excon::Error => e
        Dependabot.logger.warn("Failed to fetch module metadata for #{dependency.name}: #{e.message}")
        nil
      end

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
        token ? { "Authorization" => "Bearer #{token}" } : {}
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

        raise Dependabot::PrivateSourceAuthenticationFailure, hostname if response.status == 401
        raise error("Response from registry was #{response.status}") unless response.status == 200

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
    end
  end
end
