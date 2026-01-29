# typed: strong
# frozen_string_literal: true

require "yaml"

module Dependabot
  module Cargo
    module Helpers
      extend T::Sig

      sig { params(credentials: T::Array[Dependabot::Credential]).void }
      def self.setup_credentials_in_environment(credentials)
        credentials.each do |cred|
          next if cred["type"] != "cargo_registry"
          next if cred["registry"].nil? # this will not be present for org-level registries
          next if cred["token"].nil?

          # If there is a 'token' property, then apply it.
          # In production Dependabot-Action or Dependabot-CLI will inject the real token via the Proxy.
          token_env_var = "CARGO_REGISTRIES_#{T.must(cred['registry']).upcase.tr('-', '_')}_TOKEN"
          ENV[token_env_var] ||= cred["token"]
        end

        # And set CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS here as well, so Cargo will expect tokens
        ENV["CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS"] ||= "cargo:token"
      end
    end
  end
end
