# typed: strict
# frozen_string_literal: true

require "docker_registry2"
require "sorbet-runtime"
require "dependabot/powershell/package/package_details_fetcher"

module Dependabot
  module Powershell
    module Package
      class PackageDetailsFetcher
        class MarRegistry < DockerRegistry2::Registry
          extend T::Sig

          class InvalidManifest < DockerRegistry2::Exception; end
          class InvalidMetadata < DockerRegistry2::Exception; end

          MAR_HOST = PackageDetailsFetcher::MAR_HOST
          MAR_TOKEN_PATH = "/oauth2/token"

          sig { params(error: DockerRegistry2::RegistryHTTPException).returns(Integer) }
          def self.http_status(error)
            if error.respond_to?(:status)
              status = error.method(:status).call
              return status if status.is_a?(Integer)
            end

            status = error.message[/status (\d+)/, 1]
            return status.to_i if status

            raise error
          end

          sig do
            params(
              error: DockerRegistry2::RegistryHTTPException,
              dependency_name: String
            ).returns(Dependabot::RegistryError)
          end
          def self.registry_error(error, dependency_name)
            status = http_status(error)
            Dependabot::RegistryError.new(
              status,
              "Microsoft Artifact Registry returned HTTP #{status} while fetching #{dependency_name}"
            )
          end

          sig do
            params(
              request_url: String,
              link_url: String,
              repository: String
            ).returns(T.nilable(String))
          end
          def self.resolve_tags_page_url(request_url, link_url, repository)
            return if link_url.start_with?("//")

            uri = URI.join(request_url, link_url)
            expected_path = "/v2/#{repository}/tags/list"
            return unless uri.scheme == "https" &&
                          uri.host == MAR_HOST &&
                          uri.port == 443 &&
                          uri.userinfo.nil? &&
                          uri.path == expected_path &&
                          uri.fragment.nil?

            uri.to_s
          rescue URI::Error
            nil
          end

          sig do
            params(manifest: T::Hash[String, Object]).returns(T::Hash[String, Object])
          end
          def self.manifest_metadata(manifest)
            layers = manifest["layers"]
            layer = layers.first if layers.is_a?(Array)
            annotations = layer["annotations"] if layer.is_a?(Hash)
            metadata_json = annotations["metadata"] if annotations.is_a?(Hash)
            raise InvalidMetadata unless metadata_json.is_a?(String)

            metadata = JSON.parse(metadata_json)
            raise InvalidMetadata unless metadata.is_a?(Hash)

            metadata
          rescue JSON::ParserError
            raise InvalidMetadata, cause: nil
          end

          sig { params(repository: String, tag: String).returns(T::Hash[String, Object]) }
          def manifest(repository, tag)
            manifest = super
            raise InvalidManifest unless JSON.parse(manifest.body).is_a?(Hash)

            manifest
          rescue ArgumentError, JSON::ParserError
            raise InvalidManifest, cause: nil
          end

          private

          sig { params(header: String).returns(T.nilable(String)) }
          def authenticate_bearer(header)
            raise DockerRegistry2::RegistryAuthenticationException, cause: nil unless header.valid_encoding?

            realm = split_auth_header(header)[:realm]
            unless realm.is_a?(String) && valid_bearer_realm?(realm)
              raise DockerRegistry2::RegistryAuthenticationException, cause: nil
            end

            super
          rescue DockerRegistry2::NotFound, URI::Error
            raise DockerRegistry2::RegistryAuthenticationException, cause: nil
          end

          sig { params(realm: String).returns(T::Boolean) }
          def valid_bearer_realm?(realm)
            return false unless realm.valid_encoding?

            uri = URI.parse(realm)
            uri.scheme == "https" &&
              uri.host == MAR_HOST &&
              uri.port == 443 &&
              uri.userinfo.nil? &&
              uri.path == MAR_TOKEN_PATH &&
              uri.query.nil? &&
              uri.fragment.nil?
          rescue URI::Error
            false
          end

          sig do
            params(
              type: String,
              url: String,
              request_options: T::Hash[Symbol, Object]
            ).returns(DockerRegistry2::Response)
          end
          def perform_request(type, url, request_options = {})
            response = super
            header = response.headers[:www_authenticate] if response.code == 401
            unless response.code != 401 || (header.is_a?(String) && header.valid_encoding?)
              raise DockerRegistry2::RegistryAuthenticationException, cause: nil
            end

            response
          end

          sig { params(base_url: String).returns(Faraday::Connection) }
          def build_connection(base_url)
            Faraday.new(base_url, **connection_options) do |faraday|
              faraday.adapter :net_http
            end
          end
        end
      end
    end
  end
end
