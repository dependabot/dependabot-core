# typed: strict
# frozen_string_literal: true

require "json"
# Resource-area discovery and the service endpoints it returns are public. Keep this
# dependency on the anonymous side of the credential proxy.
require "uri"

require "dependabot/errors"

require "dependabot/azure_pipelines/package/azure_devops_http"

module Dependabot
  module AzurePipelines
    module Package
      class ResourceAreaClient
        extend T::Sig

        DISTRIBUTED_TASKS_ID = T.let("a85b8835-c1a1-4aac-ae97-1c3d0ba72dbd", String)
        EXTENSION_MANAGEMENT_ID = T.let("6c2b0933-3600-42ae-bf8b-93d4f7e83594", String)
        GALLERY_ID = T.let("69d21c00-f135-441b-b5ce-3626378e0819", String)
        API_VERSION = T.let("7.1-preview.1", String)
        GLOBAL_RESOURCE_AREA_URL = T.let(
          "https://app.vssps.visualstudio.com/_apis/resourceareas/#{GALLERY_ID}?api-version=#{API_VERSION}".freeze,
          String
        )

        @cache = T.let(nil, T.nilable(T::Hash[String, String]))

        class << self
          extend T::Sig

          sig { void }
          def clear_cache!
            @cache = nil
          end

          sig { returns(T::Hash[String, String]) }
          def cache
            @cache ||= {}
          end
        end

        sig { params(organization: AzureDevOpsOrganization).void }
        def initialize(organization:)
          @organization = organization
        end

        sig { returns(String) }
        def distributed_tasks_url
          organization_area_url(DISTRIBUTED_TASKS_ID, "distributedtask", expected_host: @organization.host)
        end

        sig { returns(String) }
        def extension_management_url
          organization_area_url(
            EXTENSION_MANAGEMENT_ID,
            "ExtensionManagement",
            expected_host: "extmgmt.dev.azure.com"
          )
        end

        sig { returns(String) }
        def marketplace_url
          self.class.cache["marketplace"] ||= begin
            discovered = discover(GLOBAL_RESOURCE_AREA_URL, "Gallery", GALLERY_ID)
            validate_location(
              discovered,
              area_name: "Gallery",
              area_id: GALLERY_ID,
              expected_host: "marketplace.visualstudio.com",
              expected_path: "/"
            )
          end
        end

        private

        sig { params(id: String, name: String, expected_host: String).returns(String) }
        def organization_area_url(id, name, expected_host:)
          key = "#{@organization.url}|#{id}"
          self.class.cache[key] ||= begin
            endpoint = "#{@organization.url}/_apis/resourceareas/#{id}?api-version=#{API_VERSION}"
            discovered = discover(endpoint, name, id)
            validate_location(
              discovered,
              area_name: name,
              area_id: id,
              expected_host: expected_host,
              expected_path: @organization.service_path(expected_host)
            )
          end
        end

        sig { params(endpoint: String, area_name: String, area_id: String).returns(String) }
        def discover(endpoint, area_name, area_id)
          response = AzureDevOpsHttp.get(url: endpoint)
          unless response.status == 200
            raise Dependabot::DependabotError,
                  "Could not resolve Azure DevOps resource area #{area_name} (#{area_id}): " \
                  "#{AzureDevOpsHttp.describe_failure(response)}"
          end

          parsed = JSON.parse(response.body)
          location = parsed.is_a?(Hash) ? parsed["locationUrl"] : nil
          return location if location.is_a?(String)

          raise Dependabot::DependabotError,
                "Azure DevOps resource area #{area_name} (#{area_id}) did not include a location URL"
        rescue JSON::ParserError
          raise Dependabot::DependabotError,
                "Could not parse Azure DevOps resource area #{area_name} (#{area_id})"
        end

        sig do
          params(
            location: String,
            area_name: String,
            area_id: String,
            expected_host: String,
            expected_path: String
          ).returns(String)
        end
        def validate_location(location, area_name:, area_id:, expected_host:, expected_path:)
          uri = URI.parse(location)
          host = uri.host&.downcase
          unless valid_location_uri?(uri)
            sanitized_url = host ? "https://#{host}#{uri.path}" : "(invalid URL)"
            raise Dependabot::DependabotError,
                  "Unexpected URL for Azure DevOps resource area #{area_name} (#{area_id}): " \
                  "#{sanitized_url}; expected HTTPS on #{expected_host}#{expected_path}"
          end

          sanitized_url = host ? "https://#{host}#{uri.path}" : "(invalid URL)"

          validate_location_host!(host, area_name, area_id, expected_host, sanitized_url)
          path = uri.path.to_s
          validate_location_path!(path, area_name, area_id, expected_path, sanitized_url)
          "https://#{T.must(host)}#{normalized_path(path)}"
        rescue URI::InvalidURIError
          raise Dependabot::DependabotError,
                "Invalid URL for Azure DevOps resource area #{area_name} (#{area_id}); " \
                "expected HTTPS on #{expected_host}#{expected_path}"
        end

        sig { params(uri: URI::Generic).returns(T::Boolean) }
        def valid_location_uri?(uri)
          uri.is_a?(URI::HTTPS) && !uri.host.nil? && uri.userinfo.nil? &&
            uri.query.nil? && uri.fragment.nil? && [nil, 443].include?(uri.port)
        end

        sig do
          params(
            host: T.nilable(String),
            area_name: String,
            area_id: String,
            expected_host: String,
            sanitized_url: String
          ).void
        end
        def validate_location_host!(host, area_name, area_id, expected_host, sanitized_url)
          return if host == expected_host

          raise Dependabot::DependabotError,
                "Azure DevOps resource area #{area_name} (#{area_id}) resolved to #{sanitized_url}, " \
                "expected host #{expected_host}; review adding #{host} to the Azure DevOps registry " \
                "proxy allowlist"
        end

        sig do
          params(path: String, area_name: String, area_id: String, expected_path: String, sanitized_url: String)
            .void
        end
        def validate_location_path!(path, area_name, area_id, expected_path, sanitized_url)
          return if normalized_path(path) == normalized_path(expected_path)

          raise Dependabot::DependabotError,
                "Azure DevOps resource area #{area_name} (#{area_id}) resolved to #{sanitized_url}, " \
                "but the path does not match the configured organization"
        end

        sig { params(path: String).returns(String) }
        def normalized_path(path)
          return "/" if path.empty?

          path.end_with?("/") ? path : "#{path}/"
        end
      end
    end
  end
end
