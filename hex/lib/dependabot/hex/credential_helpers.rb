# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Hex
    module CredentialHelpers
      extend T::Sig

      # Patterns matching Hex authentication/registry errors.
      # Shared between LockfileUpdater and VersionResolver.
      HEX_AUTH_ERROR_PATTERNS = T.let(
        [
          /No authenticated organization found for (?<repo>[a-z0-9_-]+)\./,
          /Public key fingerprint mismatch for repo "(?<repo>[a-z0-9_-]+)"/,
          /Missing credentials for "(?<repo>[a-z0-9_-]+)"/,
          /Downloading public key for repo "(?<repo>[a-z0-9_-]+)"/,
          /Registry "(?<repo>[a-z0-9_-]+)" does not serve a public key/,
          /Embedded public key fingerprint mismatch for repo "(?<repo>[a-z0-9_-]+)"/,
          /Failed to fetch record for (?<repo>[a-z0-9_-]+)(?::(?<org>[a-z0-9_-]+))?/
        ].freeze,
        T::Array[Regexp]
      )

      sig { params(credentials: T::Array[Dependabot::Credential]).returns(T::Array[Dependabot::Credential]) }
      def self.hex_credentials(credentials)
        organization_credentials(credentials) + repo_credentials(credentials)
      end

      sig { params(credentials: T.untyped).returns(T::Array[Dependabot::Credential]) }
      def self.organization_credentials(credentials)
        defaults = Dependabot::Credential.new({ "organization" => "", "token" => "" })
        keys = %w(type organization token)

        credentials
          .select { |cred| cred["type"] == "hex_organization" }
          .flat_map { |cred| defaults.merge(cred).slice(*keys).values }
      end
      sig { params(credentials: T::Array[Dependabot::Credential]).returns(T::Array[Dependabot::Credential]) }
      def self.repo_credentials(credentials)
        # Credentials are serialized as a flat array that may not have optional fields. Using a
        # default ensures that the array is always the same length, even if values are empty.
        # Empty string (not nil) is used for missing values because the flat-array serialization
        # format passed to the Elixir helper does not support nil.
        defaults = Dependabot::Credential.new(
          { "url" => "", "auth_key" => "", "public_key_fingerprint" => "", "public_key" => "" }
        )
        keys = %w(type repo url auth_key public_key_fingerprint public_key)

        credentials
          .select { |cred| cred["type"] == "hex_repository" }
          .flat_map { |cred| defaults.merge(cred).slice(*keys).values }
      end
    end
  end
end
