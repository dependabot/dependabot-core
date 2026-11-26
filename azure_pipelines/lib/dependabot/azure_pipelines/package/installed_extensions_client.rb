# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "time"

require "dependabot/logger"

require "dependabot/azure_pipelines/package/azure_devops_http"
require "dependabot/azure_pipelines/package/azure_devops_organization"
require "dependabot/azure_pipelines/package/resource_area_client"

module Dependabot
  module AzurePipelines
    module Package
      # Lists when each extension installed in an Azure DevOps organization was last
      # installed or updated, through `_apis/extensionmanagement/installedextensions`.
      #
      # An organization can only run a task version once the extension version that
      # contributes it has been published and installed, so the install time is an
      # upper bound on when every task version from that extension was released. One
      # call answers that for every extension, where the Marketplace needs one query
      # per extension.
      #
      # The answer only saves requests, so being unable to get it is never fatal: the
      # caller falls back to asking the Marketplace.
      class InstalledExtensionsClient
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
        API_VERSION = T.let("7.1-preview.1", String)

        @installed_at_cache = T.let(nil, T.nilable(T::Hash[String, T::Hash[String, Time]]))

        class << self
          extend T::Sig

          sig { returns(T::Hash[String, T::Hash[String, Time]]) }
          def installed_at_cache
            @installed_at_cache ||= {}
          end

          sig { void }
          def clear_cache!
            @installed_at_cache = nil
          end
        end

        sig { params(organization: AzureDevOpsOrganization).void }
        def initialize(organization:)
          @organization = T.let(organization, AzureDevOpsOrganization)
        end

        sig { params(extension_id: String).returns(T.nilable(Time)) }
        def installed_at(extension_id)
          installed = self.class.installed_at_cache[@organization.url] ||= fetch_installed_at
          installed[extension_id.downcase]
        end

        private

        sig { returns(T::Hash[String, Time]) }
        def fetch_installed_at
          base_url = ResourceAreaClient.new(organization: @organization).extension_management_url
          url = "#{base_url}_apis/extensionmanagement/installedextensions?api-version=#{API_VERSION}"
          response = AzureDevOpsHttp.get(url: url, headers: @organization.headers)

          unless response.status == 200 && json_response?(response)
            return unavailable(AzureDevOpsHttp.describe_failure(response))
          end

          parse(response.body)
        rescue Dependabot::DependabotError, Excon::Error => e
          unavailable(e.message)
        end

        sig { params(response: Excon::Response).returns(T::Boolean) }
        def json_response?(response)
          content_type = (response.headers["Content-Type"] || response.headers["content-type"]).to_s
          !content_type.include?("text/html") && !response.body.to_s.lstrip.start_with?("<")
        end

        sig { params(body: T.nilable(String)).returns(T::Hash[String, Time]) }
        def parse(body)
          parsed = JSON.parse(body.to_s)
          values = parsed.is_a?(Hash) ? parsed["value"] : nil
          return unavailable("the response had no extension list") unless values.is_a?(Array)

          values.each_with_object({}) do |entry, installed|
            next unless entry.is_a?(Hash)

            extension_id = extension_id(entry)
            time = install_time(entry)
            installed[extension_id] = time if extension_id && time
          end
        rescue JSON::ParserError
          unavailable("the response was not valid JSON")
        end

        sig { params(entry: JsonRecord).returns(T.nilable(String)) }
        def extension_id(entry)
          publisher = entry["publisherId"]
          extension = entry["extensionId"]
          return nil unless publisher.is_a?(String) && extension.is_a?(String)
          return nil if publisher.empty? || extension.empty?

          "#{publisher}.#{extension}".downcase
        end

        sig { params(entry: JsonRecord).returns(T.nilable(Time)) }
        def install_time(entry)
          install_state = entry["installState"]
          return nil unless install_state.is_a?(Hash)

          last_updated = T.cast(install_state, JsonRecord)["lastUpdated"]
          last_updated.is_a?(String) ? Time.parse(last_updated) : nil
        rescue ArgumentError
          nil
        end

        sig { params(reason: String).returns(T::Hash[String, Time]) }
        def unavailable(reason)
          Dependabot.logger.warn(
            "Could not list the extensions installed in #{@organization.url} (#{reason}); " \
            "dating extension tasks through the Marketplace instead. Granting the registry " \
            "credential Extensions (Read) avoids a Marketplace query per extension."
          )
          {}
        end
      end
    end
  end
end
