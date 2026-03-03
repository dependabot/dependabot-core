# typed: strict
# frozen_string_literal: true

require "toml-rb"

module Dependabot
  module Cargo
    module Helpers
      extend T::Sig

      sig do
        params(
          credentials: T::Array[Dependabot::Credential],
          cargo_config_content: T.nilable(String)
        ).void
      end
      def self.disable_cargo_credential_providers(credentials, cargo_config_content: nil)
        # Disable Cargo's built-in credential providers entirely so that Cargo does not attempt to look up registry
        # tokens on its own. The dependabot proxy (https://github.com/dependabot/proxy/) handles all registry
        # authentication transparently by intercepting HTTP requests and injecting the appropriate credentials.

        # Disable the global credential provider.
        # Uses ||= so developers can override for local development without the proxy.
        ENV["CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS"] ||= ""

        # Also disable per-registry credential providers. Per-registry `credential-provider` settings in
        # .cargo/config.toml override the global env var, so we must explicitly disable each one.
        # Collect registry names from both the credentials list and the cargo config file.
        registry_names = T.let(Set.new, T::Set[String])

        credentials.each do |cred|
          next if cred["type"] != "cargo_registry"
          next if cred["registry"].nil?

          registry_names.add(T.must(cred["registry"]))
        end

        if cargo_config_content
          begin
            parsed = TomlRB.parse(cargo_config_content)
            case parsed["registries"]
            when Hash
              parsed["registries"].each_key { |name| registry_names.add(T.cast(name, String)) }
            end
          rescue TomlRB::ParseError
            # If the config is malformed, skip parsing — the credential provider overrides from credentials
            # list alone will still help in most cases.
            Dependabot.logger.warn("Failed to parse .cargo/config.toml for registry names")
          end
        end

        registry_names.each do |name|
          env_var = "CARGO_REGISTRIES_#{name.upcase.tr('-', '_')}_CREDENTIAL_PROVIDER"
          ENV[env_var] ||= ""
        end
      end
    end
  end
end
