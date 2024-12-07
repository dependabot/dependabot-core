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
          lockfiles: T::Hash[Symbol, T.nilable(Dependabot::DependencyFile)],
          registry_config_files: T::Hash[Symbol, T.nilable(Dependabot::DependencyFile)]
        ).void
      end
      def initialize(lockfiles, registry_config_files)
        @lockfiles = T.let(lockfiles, T::Hash[Symbol, T.nilable(Dependabot::DependencyFile)])
        @registry_config_files = T.let(registry_config_files, T::Hash[Symbol, T.nilable(Dependabot::DependencyFile)])
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
        # Check .npmrc or .yarnrc first
        npm_or_yarn_config = @registry_config_files[:npmrc] || @registry_config_files[:yarnrc]
        npm_yarn_result = parse_registry_file(npm_or_yarn_config)
        return npm_yarn_result if npm_yarn_result[:registry] || npm_yarn_result[:auth_token]

        # Check yarnrc.yml next
        yarnrc_yml_config = @registry_config_files[:yarnrc_yml]
        yarnrc_result = parse_yarnrc_yml(yarnrc_yml_config)
        return yarnrc_result if yarnrc_result[:registry] || yarnrc_result[:auth_token]

        # Check lockfiles last
        lockfile_result = parse_lockfiles
        return lockfile_result if lockfile_result[:registry] || lockfile_result[:auth_token]

        # If no values are found, Corepack defaults to its own registry settings
        {}
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
          result[:auth_token] = value.strip if key.strip == AUTH_KEY
        end
        result
      end

      sig { params(file: T.nilable(Dependabot::DependencyFile)).returns(T::Hash[Symbol, T.nilable(String)]) }
      def parse_yarnrc_yml(file)
        content = file&.content
        return {} unless content

        result = {}
        yaml_data = YAML.safe_load(content, permitted_classes: [Symbol, String])
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

      sig { returns(T::Hash[Symbol, T.nilable(String)]) }
      def parse_lockfiles
        result = {}

        @lockfiles.each_value do |file|
          next unless file

          content = file.content
          next unless content

          # Extract registry URL from lockfile
          if (match = content.match(%r{"registry":\s*"(https?://[^"]+)"}))
            result[:registry] = match.captures.first
            break
          end
        end

        result
      end
    end
  end
end
