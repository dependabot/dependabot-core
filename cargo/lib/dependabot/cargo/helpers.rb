# typed: strict
# frozen_string_literal: true

require "uri"
require "toml-rb"
require "dependabot/experiments"

module Dependabot
  module Cargo
    module Helpers
      extend T::Sig

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

      # Parses cargo config content and returns the names of custom registries
      # whose index URL matches a credential host or url.
      sig { params(config_content: String, credentials: T::Array[Dependabot::Credential]).returns(T::Array[String]) }
      def self.custom_registry_names(config_content, credentials)
        parsed = TomlRB.parse(config_content)
        registries = parsed["registries"]
        return [] unless registries.is_a?(Hash)

        credential_hosts = credentials.filter_map { |cred| cred["host"] }.to_set
        credential_urls = credentials.filter_map { |cred| cred["url"]&.delete_suffix("/") }.to_set

        registries.select do |_name, config|
          config.is_a?(Hash) && registry_index_matches?(config, credential_hosts, credential_urls)
        end.keys
      rescue TomlRB::Error, URI::InvalidURIError => e
        Dependabot.logger.warn("Failed to parse cargo config for registry names: #{e.message}")
        []
      end

      sig do
        params(
          config: T::Hash[String, String],
          credential_hosts: T::Set[String],
          credential_urls: T::Set[String]
        ).returns(T::Boolean)
      end
      def self.registry_index_matches?(config, credential_hosts, credential_urls)
        index = config["index"]
        return false unless index.is_a?(String)

        # Index URLs may have a scheme prefix like "sparse+" before the actual URL
        url = index.sub(/^[a-z]+\+/, "")
        host = URI.parse(url).host

        (host && credential_hosts.include?(host)) ||
          credential_urls.include?(url.delete_suffix("/"))
      end

      # Builds a hash of environment variables for Cargo registry token auth.
      # Returns env vars like CARGO_REGISTRIES_<NAME>_TOKEN=garbage_token for each
      # matched registry, plus CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS=cargo:token.
      sig do
        params(config_content: String, credentials: T::Array[Dependabot::Credential])
          .returns(T::Hash[String, String])
      end
      def self.registry_token_env(config_content, credentials)
        registry_names = custom_registry_names(config_content, credentials)
        return {} if registry_names.empty?

        registry_names.each_with_object({}) do |name, hash|
          key = "CARGO_REGISTRIES_#{name.upcase.tr('-', '_')}_TOKEN"
          hash[key] = "garbage_token"
        end
      end

      # Convenience method: extracts .cargo/config.toml from dependency files and
      # builds registry token env vars. Returns an empty hash if no config file exists.
      sig do
        params(
          dependency_files: T::Array[Dependabot::DependencyFile],
          credentials: T::Array[Dependabot::Credential]
        ).returns(T::Hash[String, String])
      end
      def self.registry_token_env_from_files(dependency_files, credentials)
        config_file = dependency_files.find { |f| f.name == ".cargo/config.toml" }
        return {} unless config_file

        registry_token_env(T.must(config_file.content), credentials)
      end

      # Builds the complete environment variable hash for running cargo commands:
      # 1. Sets CARGO_REGISTRIES_<NAME>_TOKEN for each matched custom registry
      # 2. Merges real CARGO_REGISTR(Y|IES)_* vars from the process environment
      # 3. Sets CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS=cargo:token
      sig do
        params(
          dependency_files: T::Array[Dependabot::DependencyFile],
          credentials: T::Array[Dependabot::Credential]
        ).returns(T::Hash[String, String])
      end
      def self.cargo_command_env(dependency_files, credentials)
        ENV["CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS"] ||= ""
        return {} unless ENV.fetch("DEPENDABOT", nil) == "true"
        return {} unless Dependabot::Experiments.enabled?(:cargo_set_registry_token_auth)

        env = registry_token_env_from_files(dependency_files, credentials)
        Dependabot.logger.info("Setting registry token env vars: #{env.keys.join(', ')}") unless env.empty?
        env.merge!(ENV.select { |key, _value| key.match(/^CARGO_REGISTR(Y|IES)_/) })
        env["CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS"] = "cargo:token"
        env
      end
    end
  end
end
