# typed: strict
# frozen_string_literal: true

require "yaml"
require "dependabot/dependency_file"
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
      COREPACK_NPM_REGISTRY_ENV = "COREPACK_NPM_REGISTRY"
      COREPACK_NPM_TOKEN_ENV = "COREPACK_NPM_TOKEN"

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
        env_variables[COREPACK_NPM_REGISTRY_ENV] = registry_info[:registry] if registry_info[:registry]
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
          next unless cred["replaces-base"] # Skip if not a reverse-proxy registry

          # Set the registry if it's not already set
          registries[:registry] ||= cred["registry"]

          # Set the token if it's not already set
          registries[:auth_token] ||= cred["token"]
        end
        registries
      end

      # Find registry and token in .npmrc or .yarnrc file
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
