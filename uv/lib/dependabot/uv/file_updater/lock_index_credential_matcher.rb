# typed: strict
# frozen_string_literal: true

require "uri"
require "dependabot/uv/file_updater"

module Dependabot
  module Uv
    class FileUpdater < Dependabot::FileUpdaters::Base
      class LockIndexCredentialMatcher
        extend T::Sig

        sig { params(credentials: T::Array[Dependabot::Credential]).void }
        def initialize(credentials:)
          @credentials = credentials
        end

        sig { params(registry_url: String).returns(T.nilable(Dependabot::Credential)) }
        def best_credential_for_registry_url(registry_url)
          credential_scores = @credentials.map do |credential|
            [credential, credential_match_score(credential["index-url"].to_s, registry_url)]
          end
          best_match = credential_scores.max_by { |_, score| score }

          return nil unless best_match
          return nil if best_match[1].negative?

          best_match[0]
        end

        private

        sig { params(credential_url: String, registry_url: String).returns(Integer) }
        def credential_match_score(credential_url, registry_url)
          normalized_credential_url = normalize_index_url(credential_url)
          normalized_registry_url = normalize_index_url(registry_url)

          return 100_000 if normalized_credential_url == normalized_registry_url

          credential_uri = URI.parse(normalized_credential_url)
          registry_uri = URI.parse(normalized_registry_url)

          return -1 unless credential_uri.scheme == registry_uri.scheme
          return -1 unless credential_uri.host == registry_uri.host
          return -1 unless credential_uri.port == registry_uri.port

          credential_path = normalized_uri_path(credential_uri)
          registry_path = normalized_uri_path(registry_uri)

          return 1 if credential_path == "/"

          if registry_path.start_with?(credential_path.chomp("/") + "/")
            credential_path.length
          else
            -1
          end
        rescue URI::InvalidURIError
          -1
        end

        sig { params(url: String).returns(String) }
        def normalize_index_url(url)
          url.chomp("/")
        end

        sig { params(uri: URI::Generic).returns(String) }
        def normalized_uri_path(uri)
          path = uri.path.to_s
          path.empty? ? "/" : path
        end
      end
    end
  end
end
