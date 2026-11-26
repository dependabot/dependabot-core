# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "uri"

require "dependabot/credential"
require "dependabot/errors"

module Dependabot
  module AzurePipelines
    module Package
      # The Azure DevOps organization whose installed tasks should be used as the source
      # of truth, taken from a credential whose URL points at the organization
      # (`https://dev.azure.com/<organization>`, or the legacy
      # `https://<organization>.visualstudio.com`).
      #
      # Authentication is added by the credential proxy. Core uses only the typed
      # registry URL to select the organization; PATs and OIDC client secrets must not
      # be copied into request headers here.
      class AzureDevOpsOrganization
        extend T::Sig

        CLOUD_HOST = T.let("dev.azure.com", String)
        LEGACY_HOST_SUFFIX = T.let(".visualstudio.com", String)
        LEGACY_HOST_PATTERN = T.let(/\A[a-z0-9-]+\.visualstudio\.com\z/, Regexp)
        CREDENTIAL_TYPE = T.let("azure_devops_organization", String)

        sig { params(credentials: T::Array[Dependabot::Credential]).returns(T.nilable(AzureDevOpsOrganization)) }
        def self.from_credentials(credentials)
          organization_credentials = credentials.select { |credential| credential["type"] == CREDENTIAL_TYPE }
          return nil if organization_credentials.empty?

          if organization_credentials.length > 1
            raise Dependabot::DependabotError, "Only one Azure DevOps organization registry can be configured"
          end

          url = organization_url(T.must(organization_credentials.first)["url"])
          return new(url: url) if url

          raise Dependabot::DependabotError,
                "Azure DevOps organization registry must have a valid HTTPS organization URL"
        end

        sig { params(raw: T.nilable(String)).returns(T.nilable(String)) }
        def self.organization_url(raw)
          return nil if raw.nil? || raw.empty?

          raw_url = raw
          uri = URI.parse(raw_url.include?("://") ? raw_url : "https://#{raw_url}")
          return nil unless valid_organization_uri?(uri)

          host = T.must(uri.host).downcase
          return cloud_organization_url(uri) if host == CLOUD_HOST
          return "https://#{host}" if host.match?(LEGACY_HOST_PATTERN) && uri.path.to_s.empty?

          nil
        rescue URI::InvalidURIError
          nil
        end

        sig { params(uri: URI::Generic).returns(T::Boolean) }
        def self.valid_organization_uri?(uri)
          uri.is_a?(URI::HTTPS) && !uri.host.nil? && uri.userinfo.nil? &&
            uri.query.nil? && uri.fragment.nil? && [nil, 443].include?(uri.port)
        end

        sig { params(uri: URI::Generic).returns(T.nilable(String)) }
        def self.cloud_organization_url(uri)
          segments = uri.path.to_s.split("/").reject(&:empty?)
          return nil unless segments.length == 1

          "https://#{CLOUD_HOST}/#{segments.first}"
        end

        sig { params(url: String).void }
        def initialize(url:)
          @url = url
          uri = URI.parse(url)
          @host = T.let(T.must(uri.host), String)
          @organization = T.let(organization_name(uri), String)
        end

        sig { returns(String) }
        attr_reader :url

        sig { returns(String) }
        attr_reader :host

        sig { returns(String) }
        attr_reader :organization

        sig { params(service_host: String).returns(String) }
        def service_path(service_host)
          if service_host == host
            URI.parse(url).path.to_s
          else
            "/#{organization}"
          end
        end

        private

        sig { params(uri: URI::Generic).returns(String) }
        def organization_name(uri)
          return T.must(uri.path.to_s.split("/").reject(&:empty?).first) if @host == CLOUD_HOST

          @host.delete_suffix(LEGACY_HOST_SUFFIX)
        end

        public

        sig { returns(T::Hash[String, String]) }
        def headers
          { "Accept" => "application/json", "User-Agent" => "dependabot-core" }
        end
      end
    end
  end
end
