# typed: strict
# frozen_string_literal: true

require "base64"
require "uri"

module Dependabot
  module NpmAndYarn
    module Package
      module RegistryCredentialHelpers
        extend T::Sig
        extend T::Helpers

        abstract!

        sig { abstract.returns(T::Array[Dependabot::Credential]) }
        def credentials; end

        sig { returns(T.nilable(String)) }
        def configured_registry_from_credentials
          replaces_base_cred = credentials.find { |cred| cred["type"] == "npm_registry" && cred.replaces_base? }
          return unless replaces_base_cred&.fetch("registry", nil)

          normalize_registry_url(replaces_base_cred["registry"])
        end

        sig { params(registry: T.nilable(String)).returns(T.nilable(String)) }
        def normalize_registry_url(registry)
          return nil unless registry

          normalized_registry = registry.start_with?("http") ? registry : "https://#{registry}"
          URI::DEFAULT_PARSER.escape(normalized_registry)&.gsub(%r{/+$}, "")
        end

        sig { params(registry: String).returns(T::Hash[String, String]) }
        def auth_headers_for_registry(registry)
          token = credentials
                  .select { |cred| cred["type"] == "npm_registry" }
                  .find { |cred| normalize_registry_url(cred["registry"]) == registry }
                  &.fetch("token", nil)

          return {} unless token

          auth_header_for(token)
        end

        sig { params(token: String).returns(T::Hash[String, String]) }
        def auth_header_for(token)
          if token.include?(":")
            encoded_token = Base64.encode64(token).delete("\n")
            { "Authorization" => "Basic #{encoded_token}" }
          elsif Base64.decode64(token).ascii_only? &&
                Base64.decode64(token).include?(":")
            { "Authorization" => "Basic #{token.delete("\n")}" }
          else
            { "Authorization" => "Bearer #{token}" }
          end
        end
      end
    end
  end
end
