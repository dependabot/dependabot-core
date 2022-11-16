# frozen_string_literal: true

module Dependabot
  module Hex
    module CredentialHelpers
      def self.hex_credentials(credentials)
        organization_credentials(credentials) + repo_credentials(credentials)
      end

      def self.organization_credentials(credentials)
        defaults = { "organization" => "", "token" => "" }
        keys = %w(type organization token)

        credentials.
          select { |cred| cred["type"] == "hex_organization" }.
          flat_map { |cred| defaults.merge(cred).slice(*keys).values }
      end

      def self.repo_credentials(credentials)
        # Credentials are serialized as an array that may not have optional fields. Using a
        # default ensures that the array is always the same length, even if values are empty.
        defaults = { "url" => "", "auth_key" => "", "public_key_fingerprint" => "" }
        keys = %w(type repo url auth_key public_key_fingerprint)

        credentials.
          select { |cred| cred["type"] == "hex_repository" }.
          flat_map { |cred| defaults.merge(cred).slice(*keys).values }
      end
    end
  end
end
