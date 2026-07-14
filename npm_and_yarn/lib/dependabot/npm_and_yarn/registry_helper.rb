# typed: strict
# frozen_string_literal: true

require "json"
require "yaml"
require "dependabot/credential"
require "dependabot/dependency_file"
require "dependabot/registry_client"
require "dependabot/shared_helpers"
require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class RegistryHelper
      extend T::Sig

      # Keys for configurations
      REGISTRY_KEY = "registry"
      AUTH_KEY = "authToken"

      # Yarn-specific keys
      NPM_AUTH_TOKEN_KEY_FOR_YARN = "npmAuthToken"
      NPM_SCOPE_KEY_FOR_YARN = "npmScopes"
      NPM_REGISTER_KEY_FOR_YARN = "npmRegistryServer"

      # Environment variable keys
      COREPACK_NPM_REGISTRY_ENV = "COREPACK_NPM_REGISTRY" # For Corepack
      NPM_CONFIG_REGISTRY_ENV = "npm_config_registry" # For npm
      COREPACK_NPM_TOKEN_ENV = "COREPACK_NPM_TOKEN"
      COREPACK_INTEGRITY_KEYS_ENV = "COREPACK_INTEGRITY_KEYS"

      # Default npm registry - no need to set env vars for this
      DEFAULT_NPM_REGISTRY = "https://registry.npmjs.org"

      # Corepack signing-key endpoints
      NPM_KEYS_URL = "https://registry.npmjs.org/-/npm/v1/keys"
      KEYS_ENDPOINT_PATH = "/-/npm/v1/keys"

      # Sentinel recorded in the registry-info hash (whose values are strings) to
      # flag a replaces-base registry. Compared explicitly rather than by truthiness.
      REPLACES_BASE_FLAG = "true"

      # Cache of merged Corepack integrity keys, keyed by normalized registry URL,
      # so we fetch each registry's keys at most once per update job. A nil value
      # records that the keys could not be built, so we don't retry the fetch.
      @integrity_keys_cache = T.let({}, T::Hash[String, T.nilable(String)])

      # Canonicalise a registry URL: ensure an https:// scheme and strip any
      # trailing slashes. Used wherever a registry URL is written into an env var
      # so there is a single source of truth for URL normalisation.
      sig { params(url: String).returns(String) }
      def self.normalize_registry_url(url)
        normalized = url.start_with?("http://", "https://") ? url.dup : "https://#{url}"
        normalized.delete_suffix!("/") while normalized.end_with?("/")
        normalized
      end

      # Build the COREPACK_INTEGRITY_KEYS value for a replaces-base registry by
      # merging npm's public signing keys with the registry's own keys, so that
      # Corepack signature verification stays enabled and trusts both sources.
      #
      # The result is cached per registry for the duration of the update job.
      # Returns nil if either key set cannot be fetched: we never disable
      # verification, we simply leave COREPACK_INTEGRITY_KEYS unset so Corepack
      # keeps verifying against its bundled npm keys.
      sig { params(registry: String, auth_token: T.nilable(String)).returns(T.nilable(String)) }
      def self.corepack_integrity_keys(registry, auth_token)
        return @integrity_keys_cache[registry] if @integrity_keys_cache.key?(registry)

        @integrity_keys_cache[registry] = build_integrity_keys(registry, auth_token)
      end

      sig { params(registry: String, auth_token: T.nilable(String)).returns(T.nilable(String)) }
      private_class_method def self.build_integrity_keys(registry, auth_token)
        # Only augment Corepack's trust anchors when the registry is served over
        # TLS. Fetching keys from a plaintext http:// registry would let an on-path
        # attacker inject their own signing keys alongside a forged package, so we
        # leave COREPACK_INTEGRITY_KEYS unset (verification against npm's bundled
        # keys is preserved) rather than trusting keys fetched over http.
        unless registry.start_with?("https://")
          Dependabot.logger.warn(
            "Refusing to fetch Corepack signing keys from a non-HTTPS registry (#{registry}); " \
            "leaving COREPACK_INTEGRITY_KEYS unset."
          )
          return nil
        end

        npm_keys = fetch_signing_keys(NPM_KEYS_URL)
        registry_keys = fetch_signing_keys("#{registry}#{KEYS_ENDPOINT_PATH}", auth_token)

        if npm_keys.nil? || registry_keys.nil?
          Dependabot.logger.warn(
            "Could not fetch Corepack signing keys for #{registry}; " \
            "leaving COREPACK_INTEGRITY_KEYS unset so verification against npm's " \
            "bundled keys is preserved."
          )
          return nil
        end

        JSON.generate({ "npm" => npm_keys + registry_keys })
      end

      # Fetch the `keys` array from an npm-compatible `/-/npm/v1/keys` endpoint.
      # Returns nil on any failure (including a malformed response) so the caller
      # can fall back gracefully rather than emitting an invalid key payload.
      sig do
        params(url: String, auth_token: T.nilable(String))
          .returns(T.nilable(T::Array[T::Hash[String, Object]]))
      end
      private_class_method def self.fetch_signing_keys(url, auth_token = nil)
        headers = auth_token ? { "Authorization" => "Bearer #{auth_token}" } : {}
        # Do not follow redirects: a signing-key endpoint that redirects (e.g. an
        # https -> http downgrade) must not silently move the fetch onto plaintext,
        # so any redirect is treated as a failure (non-200 -> nil).
        no_redirect_middlewares =
          Dependabot::SharedHelpers.excon_middleware.reject { |m| m == Excon::Middleware::RedirectFollower }
        response = Dependabot::RegistryClient.get(
          url: url,
          headers: headers,
          options: { middlewares: no_redirect_middlewares }
        )
        return nil unless response.status == 200

        keys = JSON.parse(response.body)["keys"]
        valid_signing_keys?(keys) ? keys : nil
      rescue StandardError => e
        Dependabot.logger.warn("Failed to fetch Corepack signing keys from #{url}: #{e.message}")
        nil
      end

      # A valid signing-key set is a non-empty array whose every entry is an object
      # with at least a string keyid and key. An empty or malformed set is rejected
      # so callers take the fail-safe path rather than emitting an invalid payload.
      sig { params(keys: T.nilable(Object)).returns(T::Boolean) }
      private_class_method def self.valid_signing_keys?(keys)
        return false unless keys.is_a?(Array) && !keys.empty?

        keys.all? { |k| k.is_a?(Hash) && k["keyid"].is_a?(String) && k["key"].is_a?(String) }
      end

      sig do
        params(
          registry_config_files: T::Hash[Symbol, T.nilable(Dependabot::DependencyFile)],
          credentials: T.nilable(T::Array[Dependabot::Credential])
        ).void
      end
      def initialize(registry_config_files, credentials)
        @registry_config_files = T.let(registry_config_files, T::Hash[Symbol, T.nilable(Dependabot::DependencyFile)])
        @credentials = T.let(credentials, T.nilable(T::Array[Dependabot::Credential]))
      end

      sig { returns(T::Hash[String, String]) }
      def find_corepack_env_variables
        registry_info = find_registry_and_token

        env_variables = {}

        if (raw_registry = registry_info[:registry])
          registry = RegistryHelper.normalize_registry_url(raw_registry)

          unless registry == DEFAULT_NPM_REGISTRY
            env_variables[COREPACK_NPM_REGISTRY_ENV] = registry # For Corepack
            env_variables[NPM_CONFIG_REGISTRY_ENV] = registry # For npm
            env_variables[REGISTRY_KEY] = registry

            # A replaces-base registry (e.g. Cloudsmith) is a caching proxy that
            # re-signs packages with its own keys, so Corepack's default npm-only
            # signature verification fails against it. Rather than disabling the
            # check, merge npm's public keys with the registry's own keys so that
            # verification stays enabled and trusts both sources. See issue #15567.
            if registry_info[:replaces_base] == REPLACES_BASE_FLAG
              integrity_keys = RegistryHelper.corepack_integrity_keys(registry, registry_info[:auth_token])
              env_variables[COREPACK_INTEGRITY_KEYS_ENV] = integrity_keys if integrity_keys
            end
          end
        end

        env_variables[COREPACK_NPM_TOKEN_ENV] = registry_info[:auth_token] if registry_info[:auth_token]

        env_variables
      end

      private

      sig { returns(T::Hash[Symbol, T.nilable(String)]) }
      def find_registry_and_token
        # Step 1: Check dependabot.yml configuration
        dependabot_config = config_npm_registry_and_token
        return dependabot_config if dependabot_config[:registry]

        # Step 2: Check .npmrc
        npmrc_config = @registry_config_files[:npmrc]
        npmrc_result = parse_registry_from_npmrc_yarnrc(npmrc_config, "=", "npm")

        return npmrc_result if npmrc_result[:registry]

        # Step 3: Check .yarnrc
        yarnrc_config = @registry_config_files[:yarnrc]
        yarnrc_result = parse_registry_from_npmrc_yarnrc(yarnrc_config, " ", "npm")
        return yarnrc_result if yarnrc_result[:registry]

        # Step 4: Check yarnrc.yml
        yarnrc_yml_config = @registry_config_files[:yarnrc_yml]
        yarnrc_yml_result = parse_npm_from_yarnrc_yml(yarnrc_yml_config)
        return yarnrc_yml_result if yarnrc_yml_result[:registry]

        # Default values if no registry is found
        {}
      end

      sig { returns(T::Hash[Symbol, T.nilable(String)]) }
      def config_npm_registry_and_token
        registries = {}

        return registries unless @credentials&.any?

        @credentials.each do |cred|
          next unless cred["type"] == "npm_registry" # Skip if not an npm registry
          next unless credential_replaces_base?(cred) # Skip if not a reverse-proxy registry

          # Set the registry if it's not already set
          registries[:registry] ||= cred["registry"]

          # Set the token if it's not already set
          registries[:auth_token] ||= cred["token"]

          # Flag that this registry replaces the base (reverse-proxy / caching
          # proxy), so Corepack's signature keys must be augmented with its own.
          registries[:replaces_base] ||= REPLACES_BASE_FLAG
        end

        registries
      end

      # Whether a credential is a reverse-proxy registry that replaces the base.
      # Handles both Credential objects and plain hashes; mirrors Credential's own
      # `replaces-base == true` check so a truthy non-boolean (e.g. "false") does
      # not enable replaces-base behaviour.
      sig { params(cred: T.any(Dependabot::Credential, T::Hash[String, Object])).returns(T::Boolean) }
      def credential_replaces_base?(cred)
        return cred.replaces_base? if cred.is_a?(Dependabot::Credential)

        cred["replaces-base"] == true
      end
      sig do
        params(
          file: T.nilable(Dependabot::DependencyFile),
          separator: String
        ).returns(T::Hash[Symbol, T.nilable(String)])
      end
      def parse_npm_from_npm_or_yarn_rc(file, separator = "=")
        parse_registry_from_npmrc_yarnrc(file, separator, NpmPackageManager::NAME)
      end

      # Find registry and token in .npmrc or .yarnrc file
      sig do
        params(
          file: T.nilable(Dependabot::DependencyFile),
          separator: String,
          scope: T.nilable(String)
        ).returns(T::Hash[Symbol, T.nilable(String)])
      end
      def parse_registry_from_npmrc_yarnrc(file, separator = "=", scope = nil)
        content = file&.content
        return { registry: nil, auth_token: nil } unless content

        global_registry = T.let(nil, T.nilable(String))
        scoped_registry = T.let(nil, T.nilable(String))
        auth_token = T.let(nil, T.nilable(String))

        content.split("\n").each do |line|
          # Split using the provided separator
          key, value = line.strip.split(separator, 2)
          next unless key && value

          # Remove surrounding quotes from keys and values
          cleaned_key = key.strip.gsub(/\A["']|["']\z/, "")
          cleaned_value = value.strip.gsub(/\A["']|["']\z/, "")

          case cleaned_key
          when "registry"
            # Case 1: Found a global registry
            global_registry = cleaned_value
          when "_authToken"
            # Case 2: Found an auth token
            auth_token = cleaned_value
          else
            # Handle scoped registry if a scope is provided
            scoped_registry = cleaned_value if scope && cleaned_key == "@#{scope}:registry"
          end
        end

        # Determine the registry to return (global first, fallback to scoped)
        registry = global_registry || scoped_registry

        { registry: registry, auth_token: auth_token }
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { params(file: T.nilable(Dependabot::DependencyFile)).returns(T::Hash[Symbol, T.nilable(String)]) }
      def parse_npm_from_yarnrc_yml(file)
        content = file&.content
        return { registry: nil, auth_token: nil } unless content

        result = {}
        yaml_data = safe_load_yaml(content)

        # Step 1: Extract global registry and auth token
        result[:registry] = yaml_data[NPM_REGISTER_KEY_FOR_YARN] if yaml_data.key?(NPM_REGISTER_KEY_FOR_YARN)
        result[:auth_token] = yaml_data[NPM_AUTH_TOKEN_KEY_FOR_YARN] if yaml_data.key?(NPM_AUTH_TOKEN_KEY_FOR_YARN)

        # Step 2: Fallback to any scoped registry and auth token if global is missing
        if result[:registry].nil? && yaml_data.key?(NPM_SCOPE_KEY_FOR_YARN)
          yaml_data[NPM_SCOPE_KEY_FOR_YARN].each do |_current_scope, config|
            next unless config.is_a?(Hash)

            result[:registry] ||= config[NPM_REGISTER_KEY_FOR_YARN]
            result[:auth_token] ||= config[NPM_AUTH_TOKEN_KEY_FOR_YARN]
          end
        end

        result
      end
      # rubocop:enable Metrics/PerceivedComplexity

      # Safely loads the YAML content and logs any parsing errors
      sig { params(content: String).returns(T::Hash[String, T.untyped]) }
      def safe_load_yaml(content)
        YAML.safe_load(content, permitted_classes: [Symbol, String]) || {}
      rescue Psych::SyntaxError => e
        # Log the error instead of raising it
        Dependabot.logger.error("YAML parsing error: #{e.message}")
        {}
      end
    end
  end
end
