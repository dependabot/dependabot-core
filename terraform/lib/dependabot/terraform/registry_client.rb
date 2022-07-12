# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/source"
require "dependabot/terraform/version"

module Dependabot
  module Terraform
    # Terraform::RegistryClient is a basic API client to interact with a
    # terraform registry: https://www.terraform.io/docs/registry/api.html
    class RegistryClient
      PUBLIC_HOSTNAME = "registry.terraform.io"

      def initialize(hostname: PUBLIC_HOSTNAME, credentials: [])
        @hostname = hostname
        @tokens = credentials.each_with_object({}) do |item, memo|
          memo[item["host"]] = item["token"] if item["type"] == "terraform_registry"
        end
      end

      # Fetch all the versions of a provider, and return a Version
      # representation of them.
      #
      # @param identifier [String] the identifier for the dependency, i.e:
      # "hashicorp/aws"
      # @return [Array<Dependabot::Terraform::Version>]
      # @raise [Dependabot::DependabotError] when the versions cannot be retrieved
      def all_provider_versions(identifier:)
        base_url = service_url_for("providers.v1")
        response = http_get!(URI.join(base_url, "#{identifier}/versions"))

        JSON.parse(response.body).
          fetch("versions").
          map { |release| version_class.new(release.fetch("version")) }
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
      def all_module_versions(identifier:)
        base_url = service_url_for("modules.v1")
        response = http_get!(URI.join(base_url, "#{identifier}/versions"))

        JSON.parse(response.body).
          fetch("modules").first.fetch("versions").
          map { |release| version_class.new(release.fetch("version")) }
      end

      # Fetch the "source" for a module or provider. We use the API to fetch
      # the source for a dependency, this typically points to a source code
      # repository, and then instantiate a Dependabot::Source object that we
      # can use to fetch Metadata about a specific version of the dependency.
      #
      # @param dependency [Dependabot::Dependency] the dependency who's source
      # we're attempting to find
      # @return [nil, Dependabot::Source]
      def source(dependency:)
        type = dependency.requirements.first[:source][:type]
        base_url = service_url_for(service_key_for(type))
        case type
        when "module", "modules", "registry"
          response = http_get(URI.join(base_url, "#{dependency.name}/#{dependency.version}/download"))
          return nil unless response.status == 204

          source_url = response.headers.fetch("X-Terraform-Get")
        when "provider", "providers"
          response = http_get(URI.join(base_url, "#{dependency.name}/#{dependency.version}"))
          return nil unless response.status == 200

          source_url = JSON.parse(response.body).fetch("source")
        end

        Source.from_url(source_url) if source_url
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
      def service_url_for(service_key)
        url_for(services.fetch(service_key))
      rescue KeyError
        raise Dependabot::PrivateSourceAuthenticationFailure, "Host does not support required Terraform-native service"
      end

      private

      attr_reader :hostname, :tokens

      def version_class
        Version
      end

      def headers_for(hostname)
        token = tokens[hostname]
        token ? { "Authorization" => "Bearer #{token}" } : {}
      end

      def services
        @services ||=
          begin
            response = http_get(url_for("/.well-known/terraform.json"))
            response.status == 200 ? JSON.parse(response.body) : {}
          end
      end

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

      def http_get(url)
        Excon.get(url.to_s, idempotent: true, **SharedHelpers.excon_defaults(headers: headers_for(hostname)))
      end

      def http_get!(url)
        response = http_get(url)

        raise Dependabot::PrivateSourceAuthenticationFailure, hostname if response.status == 401
        raise error("Response from registry was #{response.status}") unless response.status == 200

        response
      end

      def url_for(path)
        uri = URI.parse(path)
        return uri.to_s if uri.scheme == "https"
        raise error("Unsupported scheme provided") if uri.host && uri.scheme

        uri.host = hostname
        uri.scheme = "https"
        uri.to_s
      end

      def error(message)
        Dependabot::DependabotError.new(message)
      end
    end
  end
end
