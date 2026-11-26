# typed: strong
# frozen_string_literal: true

require "excon"
require "json"
require "sorbet-runtime"
require "time"

require "dependabot/errors"

require "dependabot/azure_pipelines/package/azure_devops_http"
require "dependabot/azure_pipelines/package/azure_devops_organization"
require "dependabot/azure_pipelines/package/resource_area_client"

module Dependabot
  module AzurePipelines
    module Package
      # Looks up Marketplace release dates for task versions contributed by an
      # extension. The credential proxy authenticates this route, including private
      # extensions; core never forwards registry secrets itself.
      class MarketplaceClient
        extend T::Sig

        JsonValue = T.type_alias do
          T.nilable(
            T.any(
              String,
              Integer,
              Float,
              T::Boolean,
              T::Array[T.anything],
              T::Hash[String, T.anything]
            )
          )
        end
        JsonRecord = T.type_alias { T::Hash[String, JsonValue] }
        QueryCriterion = T.type_alias { T::Hash[String, T.any(Integer, String)] }
        QueryFilter = T.type_alias { T::Hash[String, T.any(Integer, T::Array[QueryCriterion])] }
        Query = T.type_alias { T::Hash[String, T.any(Integer, T::Array[QueryFilter])] }

        ITEM_URL = T.let("https://marketplace.visualstudio.com/items?itemName=", String)
        FILTER_BY_EXTENSION_NAME = T.let(7, Integer)
        INCLUDE_VERSIONS = T.let(1, Integer)
        API_VERSION = T.let("7.1-preview.1", String)

        @version_dates_cache = T.let(nil, T.nilable(T::Hash[String, T::Hash[String, Time]]))

        class << self
          extend T::Sig

          sig { returns(T::Hash[String, T::Hash[String, Time]]) }
          def version_dates_cache
            @version_dates_cache ||= {}
          end

          sig { void }
          def clear_cache!
            @version_dates_cache = nil
          end

          sig { params(extension_id: String).returns(String) }
          def item_url(extension_id)
            "#{ITEM_URL}#{extension_id}"
          end
        end

        sig { params(extension_id: String, version: String).returns(T.nilable(Time)) }
        def published_at(extension_id, version)
          key = "#{@organization.url}|#{extension_id.downcase}"
          dates = self.class.version_dates_cache[key] ||= fetch_version_dates(extension_id)
          dates[version]
        end

        sig { params(organization: AzureDevOpsOrganization).void }
        def initialize(organization:)
          @organization = T.let(organization, AzureDevOpsOrganization)
        end

        private

        sig { params(extension_id: String).returns(T::Hash[String, Time]) }
        def fetch_version_dates(extension_id)
          marketplace_url = ResourceAreaClient.new(organization: @organization).marketplace_url
          query_url = "#{marketplace_url}_apis/public/gallery/extensionquery"
          response = marketplace_request(query_url, extension_id)
          validate_response!(response, query_url, extension_id)
          parse_version_dates(response.body, extension_id)
        end

        sig { params(query_url: String, extension_id: String).returns(Excon::Response) }
        def marketplace_request(query_url, extension_id)
          AzureDevOpsHttp.post(
            url: query_url,
            body: JSON.generate(query(extension_id)),
            headers: {
              "Accept" => "application/json;api-version=#{API_VERSION}",
              "Content-Type" => "application/json"
            }
          )
        end

        sig { params(response: Excon::Response, query_url: String, extension_id: String).void }
        def validate_response!(response, query_url, extension_id)
          raise Dependabot::PrivateSourceAuthenticationFailure, query_url if authentication_failure?(response)

          return if response.status == 200

          raise Dependabot::DependabotError,
                "Could not look up Marketplace extension #{extension_id} " \
                "(#{AzureDevOpsHttp.describe_failure(response)})"
        end

        sig { params(response: Excon::Response).returns(T::Boolean) }
        def authentication_failure?(response)
          content_type = (response.headers["Content-Type"] || response.headers["content-type"]).to_s
          html_body = response.body.to_s.lstrip.match?(/\A(?:<!doctype\s+html|<html)\b/i)

          [203, 401, 403].include?(response.status) ||
            (300..399).cover?(response.status) ||
            (response.status == 200 && (content_type.include?("text/html") || html_body))
        end

        sig { params(body: T.nilable(String), extension_id: String).returns(T::Hash[String, Time]) }
        def parse_version_dates(body, extension_id)
          parsed = T.cast(JSON.parse(body.to_s), JsonRecord)
          results = response_array(parsed, "results", extension_id)
          return {} if results.empty?

          extensions = response_array(T.must(results.first), "extensions", extension_id)
          return {} if extensions.empty?

          versions = response_array(T.must(extensions.first), "versions", extension_id)
          version_dates(versions)
        rescue JSON::ParserError
          raise Dependabot::DependabotError, "Could not parse Marketplace versions of #{extension_id}"
        rescue TypeError
          raise Dependabot::DependabotError, "Unexpected Marketplace response for #{extension_id}"
        end

        sig { params(value: JsonRecord, key: String, extension_id: String).returns(T::Array[JsonRecord]) }
        def response_array(value, key, extension_id)
          list = value[key]
          return T.let(list, T::Array[JsonRecord]) if list.is_a?(Array)

          raise Dependabot::DependabotError, "Unexpected Marketplace #{key} for #{extension_id}"
        end

        sig { params(versions: T::Array[JsonRecord]).returns(T::Hash[String, Time]) }
        def version_dates(versions)
          versions.each_with_object({}) do |entry, dates|
            version = entry["version"]
            last_updated = entry["lastUpdated"]
            next unless version.is_a?(String) && last_updated.is_a?(String)

            dates[version] = Time.parse(last_updated)
          rescue ArgumentError
            next
          end
        end

        sig { params(extension_id: String).returns(Query) }
        def query(extension_id)
          {
            "filters" => [{
              "criteria" => [{ "filterType" => FILTER_BY_EXTENSION_NAME, "value" => extension_id }],
              "pageNumber" => 1,
              "pageSize" => 1
            }],
            "flags" => INCLUDE_VERSIONS
          }
        end
      end
    end
  end
end
