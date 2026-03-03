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
    end
  end
end
