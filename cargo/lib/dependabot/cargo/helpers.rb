# typed: strong
# frozen_string_literal: true

module Dependabot
  module Cargo
    module Helpers
      extend T::Sig

      sig { void }
      def self.bypass_cargo_credential_providers
        # Disable Cargo's built-in credential providers entirely so that Cargo does not attempt to look up registry
        # tokens on its own. The dependabot proxy (https://github.com/dependabot/proxy/) handles all registry
        # authentication transparently by intercepting HTTP requests and injecting the appropriate credentials.
        #
        # Uses ||= so developers can override by setting CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS=cargo:token in their
        # shell (along with the appropriate CARGO_REGISTRIES_{NAME}_TOKEN vars) for local development without the proxy.
        ENV["CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS"] ||= ""
      end

      sig { params(config_content: String).returns(String) }
      def self.sanitize_cargo_config(config_content)
        # Remove per-registry `credential-provider` settings from .cargo/config.toml.
        #
        # Users may configure their repos with lines like:
        #   [registries.my-registry]
        #   credential-provider = "cargo:token"
        #
        # These per-registry settings override the global CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS env var,
        # causing Cargo to look up tokens via CARGO_REGISTRIES_{NAME}_TOKEN env vars. Since the dependabot proxy
        # handles authentication by intercepting HTTP requests, we need to strip these so Cargo makes plain
        # requests that the proxy can decorate with credentials.
        config_content.gsub(/^\s*credential-provider\s*=.*$/, "")
      end
    end
  end
end
