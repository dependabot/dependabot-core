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
        npmrc_result = parse_registry_file(npmrc_config)

        return npmrc_result if npmrc_result[:registry]

        # Step 3: Check .yarnrc
        yarnrc_config = @registry_config_files[:yarnrc]
        yarnrc_result = parse_registry_file(yarnrc_config)
        return yarnrc_result if yarnrc_result[:registry]

        # Step 4: Check yarnrc.yml
        yarnrc_yml_config = @registry_config_files[:yarnrc_yml]
        yarnrc_yml_result = parse_yarnrc_yml(yarnrc_yml_config)
        return yarnrc_yml_result if yarnrc_yml_result[:registry]

        # Default values if no registry is found
        {}
      end

      sig { returns(T::Hash[Symbol, T.nilable(String)]) }
      def config_npm_registry_and_token
        registries = {}

        return registries unless @credentials&.any?

        @credentials.each do |cred|
          next unless cred["type"] == "npm_registry"

          # Set the registry if it's not already set
          registries[:registry] ||= cred["registry"]

          # Set the token if it's not already set
          registries[:auth_token] ||= cred["token"]
        end
        registries
      end

      sig { params(file: T.nilable(Dependabot::DependencyFile)).returns(T::Hash[Symbol, T.nilable(String)]) }
      def parse_registry_file(file)
        content = file&.content
        return {} unless content

        result = {}
        content.split("\n").each do |line|
          key, value = line.split("=", 2)
          next unless key && value

          result[:registry] = value.strip if key.strip == REGISTRY_KEY
          result[:auth_token] = value.strip if key.strip == "_#{AUTH_KEY}"
        end
        result
      end

      sig { params(file: T.nilable(Dependabot::DependencyFile)).returns(T::Hash[Symbol, T.nilable(String)]) }
      def parse_yarnrc_yml(file)
        content = file&.content
        return {} unless content

        result = {}
        yaml_data = YAML.safe_load(content, permitted_classes: [Symbol, String]) || {}
        result[:registry] = yaml_data[NPM_REGISTER_KEY_FOR_YARN] if yaml_data.key?(NPM_REGISTER_KEY_FOR_YARN)
        result[:auth_token] = yaml_data[NPM_AUTH_TOKEN_KEY_FOR_YARN] if yaml_data.key?(NPM_AUTH_TOKEN_KEY_FOR_YARN)

        if yaml_data.key?(NPM_SCOPE_KEY_FOR_YARN)
          yaml_data[NPM_SCOPE_KEY_FOR_YARN].each do |_scope, config|
            result[:registry] ||= config[NPM_REGISTER_KEY_FOR_YARN]
            result[:auth_token] ||= config[NPM_AUTH_TOKEN_KEY_FOR_YARN]
          end
        end
        result
      end
    end
  end
end
