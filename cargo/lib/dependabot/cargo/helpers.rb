# typed: strong
# frozen_string_literal: true

module Dependabot
  module Cargo
    module Helpers
      extend T::Sig

      sig { params(credentials: T::Array[Dependabot::Credential]).void }
      def self.setup_credentials_in_environment(credentials)
        credentials.each do |cred|
          next if cred["type"] != "cargo_registry"
          next if cred["registry"].nil? # org-level registries won't have this; the proxy handles them

          # Build the CARGO_REGISTRIES_{NAME}_TOKEN env var that Cargo uses to authenticate with the registry.
          token_env_var = "CARGO_REGISTRIES_#{T.must(cred['registry']).upcase.tr('-', '_')}_TOKEN"

          if cred["token"]
            # Token is present — use it directly. This is the case for repo-level configs with explicit tokens
            # and for the dependabot-action when it passes credentials directly (not through the proxy).
            Dependabot.logger.info(
              "Token found for #{cred['registry']}, setting #{token_env_var} to provided token value"
            )
            ENV[token_env_var] ||= cred["token"]
          else
            # No token means we are running behind the dependabot proxy, which strips tokens from credentials
            # and re-injects them by intercepting HTTP requests. We still need to set a placeholder so that
            # Cargo believes the registry is configured and proceeds to make the HTTP request (which the proxy
            # will then authenticate). Without this, Cargo fails with "no token found for <registry>".
            Dependabot.logger.info("No token found for #{cred['registry']}, proxy will inject credentials")
            ENV[token_env_var] ||= "placeholder_token"
          end
        end

        # Tell Cargo to use token-based auth for all registries.
        ENV["CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS"] ||= "cargo:token"
      end
    end
  end
end
