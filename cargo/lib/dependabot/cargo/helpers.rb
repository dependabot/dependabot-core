# typed: strict
# frozen_string_literal: true

require "toml-rb"
require "dependabot/errors"

module Dependabot
  module Cargo
    module Helpers
      extend T::Sig

      # Disable Cargo's *global* credential providers so that Cargo does not attempt to look up registry tokens
      # on its own. The dependabot proxy (https://github.com/dependabot/proxy/) handles all registry authentication
      # transparently by intercepting HTTP requests and injecting the appropriate credentials.
      #
      # Note: this only affects the global/default credential provider. Per-registry `credential-provider` settings
      # in .cargo/config.toml override this env var, so those are stripped separately by `sanitize_cargo_config`.
      #
      # Uses ||= so developers can override by setting CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS=cargo:token in their
      # shell (along with the appropriate CARGO_REGISTRIES_{NAME}_TOKEN vars) for local development without the proxy.
      sig { void }
      def self.bypass_cargo_credential_providers
        ENV["CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS"] ||= ""
      end

      # Matches the URL in Cargo registry fetch failure messages, e.g.:
      #   failed to download from `https://index.crates.io/li/ba/libadwaita`
      REGISTRY_FETCH_FAILED_REGEX = T.let(/failed to download from `(?<url>[^`]+)`/, Regexp)

      # Fallback registry name used when no URL can be extracted from the error message
      CRATES_IO_DEFAULT_REGISTRY = T.let("index.crates.io", String)

      # Returns true when a Cargo error message indicates a transient HTTP protocol
      # error from the registry (curl error 8 "Weird server reply" / "Invalid status line").
      sig { params(message: String).returns(T::Boolean) }
      def self.registry_download_error?(message)
        message.include?("Weird server reply") || message.include?("Invalid status line")
      end

      # Extracts the registry URL from a Cargo registry fetch failure message,
      # falling back to the default crates.io registry URL when no URL is found.
      sig { params(message: String).returns(String) }
      def self.extract_registry_url(message)
        match = REGISTRY_FETCH_FAILED_REGEX.match(message)
        match ? T.must(match[:url]) : CRATES_IO_DEFAULT_REGISTRY
      end

      # Strip per-registry `credential-provider` settings from .cargo/config.toml.
      #
      # Users may have entries like:
      #   [registries.my-registry]
      #   credential-provider = "cargo:token"
      #
      # These per-registry settings override the global CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS env var,
      # causing Cargo to look up tokens locally. Since the dependabot proxy handles all registry authentication
      # transparently, we remove these so Cargo makes plain unauthenticated requests that the proxy can intercept.
      sig { params(config_content: String).returns(String) }
      def self.sanitize_cargo_config(config_content)
        parsed = TomlRB.parse(config_content)
        return config_content unless parsed.is_a?(Hash)

        registries = parsed["registries"]
        if registries.is_a?(Hash)
          registries.each_value do |registry_config|
            registry_config.delete("credential-provider") if registry_config.is_a?(Hash)
          end
        end

        # Also strip credential-provider from [registry] (crates.io default registry). Users who `cargo publish`
        # from CI may have this set. It's a per-registry override that takes precedence over the global env var,
        # so we need to remove it to prevent Cargo from trying to look up a token.
        registry = parsed["registry"]
        registry.delete("credential-provider") if registry.is_a?(Hash)

        TomlRB.dump(parsed)
      rescue TomlRB::Error => e
        raise Dependabot::DependencyFileNotParseable.new(
          ".cargo/config.toml",
          "Failed to parse Cargo config file: #{e.message}"
        )
      end
    end
  end
end
