# typed: strict
# frozen_string_literal: true

require "dependabot/config/update_config"
require "sorbet-runtime"

module Dependabot
  module Config
    # Configuration for the repository, a parsed dependabot.yaml.
    class File
      extend T::Sig

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      attr_reader :updates

      sig { returns(T::Hash[Symbol, T::Hash[Symbol, String]]) }
      attr_reader :registries

      sig do
        params(
          updates: T.nilable(T::Array[T::Hash[Symbol, String]]),
          registries: T.nilable(T::Hash[Symbol, T::Hash[Symbol, String]])
        )
          .void
      end
      def initialize(updates:, registries: nil)
        @updates = T.let(updates || [], T::Array[T::Hash[Symbol, String]])
        @registries = T.let(registries || {}, T::Hash[Symbol, T::Hash[Symbol, String]])
      end

      sig do
        params(package_manager: String, directory: T.nilable(String), target_branch: T.nilable(String))
          .returns(UpdateConfig)
      end
      def update_config(package_manager, directory: nil, target_branch: nil)
        dir = directory || "/"
        package_ecosystem = REVERSE_PACKAGE_MANAGER_LOOKUP.fetch(package_manager, "dummy")
        cfg = updates.find do |u|
          u[:"package-ecosystem"] == package_ecosystem && u[:directory] == dir &&
            (target_branch.nil? || u[:"target-branch"] == target_branch)
        end
        UpdateConfig.new(
          ignore_conditions: ignore_conditions(cfg),
          commit_message_options: commit_message_options(cfg),
          exclude_paths: exclude_paths(cfg)
        )
      end

      # Parse the YAML config file
      sig { params(config: String).returns(File) }
      def self.parse(config)
        parsed = YAML.safe_load(config, symbolize_names: true, aliases: true)
        version = parsed[:version]
        raise InvalidConfigError, "invalid version #{version}" if version && version != 2

        File.new(updates: parsed[:updates], registries: parsed[:registries])
      end

      private

      PACKAGE_MANAGER_LOOKUP = T.let(
        {
          "bazel" => "bazel",
          "bun" => "bun",
          "bundler" => "bundler",
          "cargo" => "cargo",
          "composer" => "composer",
          "deno" => "deno",
          "conda" => "conda",
          "devcontainer" => "devcontainers",
          "docker-compose" => "docker_compose",
          "docker" => "docker",
          "dotnet-sdk" => "dotnet_sdk",
          "elm" => "elm",
          "github-actions" => "github_actions",
          "gitsubmodule" => "submodules",
          "gomod" => "go_modules",
          "gradle" => "gradle",
          "helm" => "helm",
          "julia" => "julia",
          "maven" => "maven",
          "mix" => "hex",
          "nix" => "nix",
          "npm" => "npm_and_yarn",
          "nuget" => "nuget",
          "opentofu" => "opentofu",
          "pip" => "pip",
          "pre-commit" => "pre_commit",
          "pub" => "pub",
          "rust-toolchain" => "rust_toolchain",
          "sbt" => "sbt",
          "swift" => "swift",
          "terraform" => "terraform",
          "uv" => "uv",
          "vcpkg" => "vcpkg"
        }.freeze,
        T::Hash[String, String]
      )

      REVERSE_PACKAGE_MANAGER_LOOKUP = T.let(
        PACKAGE_MANAGER_LOOKUP.invert.freeze,
        T::Hash[String, String]
      )

      sig { params(cfg: T.nilable(T::Hash[Symbol, T.anything])).returns(T::Array[IgnoreCondition]) }
      def ignore_conditions(cfg)
        array_values(cfg&.dig(:ignore)).map do |raw|
          ic = hash_values(raw)
          IgnoreCondition.new(
            dependency_name: T.must(string_value(ic[:"dependency-name"])),
            versions: string_array(ic[:versions]),
            update_types: string_array(ic[:"update-types"])
          )
        end
      end

      sig do
        params(cfg: T.nilable(T::Hash[Symbol, T.anything])).returns(UpdateConfig::CommitMessageOptions)
      end
      def commit_message_options(cfg)
        commit_message = hash_values(cfg&.dig(:"commit-message"))
        prefix = string_value(commit_message[:prefix])
        UpdateConfig::CommitMessageOptions.new(
          prefix: prefix,
          prefix_development: string_value(commit_message[:"prefix-development"]) || prefix,
          include: string_value(commit_message[:include])
        )
      end

      sig { params(cfg: T.nilable(T::Hash[Symbol, T.anything])).returns(T::Array[String]) }
      def exclude_paths(cfg)
        string_array(cfg&.dig(:"exclude-paths")) || []
      end

      # The methods below narrow the loosely typed, parsed-YAML config values
      # (Symbol-keyed hashes whose values are arbitrary) into the specific
      # types the config objects expect.

      sig { params(value: T.anything).returns(T.nilable(String)) }
      def string_value(value)
        case value
        when String then value
        end
      end

      sig { params(value: T.anything).returns(T::Hash[Symbol, T.anything]) }
      def hash_values(value)
        case value
        when Hash then value
        else {}
        end
      end

      sig { params(value: T.anything).returns(T::Array[T.anything]) }
      def array_values(value)
        case value
        when Array then value
        else []
        end
      end

      sig { params(value: T.anything).returns(T.nilable(T::Array[String])) }
      def string_array(value)
        case value
        when Array then value.map(&:to_s)
        end
      end
    end
  end
end
