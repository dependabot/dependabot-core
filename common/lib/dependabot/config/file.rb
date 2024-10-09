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
        package_ecosystem = PACKAGE_MANAGER_LOOKUP.invert.fetch(package_manager)
        cfg = updates.find do |u|
          u[:"package-ecosystem"] == package_ecosystem && u[:directory] == dir &&
            (target_branch.nil? || u[:"target-branch"] == target_branch)
        end
        UpdateConfig.new(
          ignore_conditions: ignore_conditions(cfg),
          commit_message_options: commit_message_options(cfg)
        )
      end

      # Parse the YAML config file
      sig { params(config: String).returns(File) }
      def self.parse(config)
        parsed = YAML.safe_load(config, symbolize_names: true)
        version = parsed[:version]
        raise InvalidConfigError, "invalid version #{version}" if version && version != 2

        File.new(updates: parsed[:updates], registries: parsed[:registries])
      end

      private

      PACKAGE_MANAGER_LOOKUP = T.let({
        "bundler" => "bundler",
        "cargo" => "cargo",
        "composer" => "composer",
        "devcontainer" => "devcontainers",
        "docker" => "docker",
        "elm" => "elm",
        "github-actions" => "github_actions",
        "gitsubmodule" => "submodules",
        "gomod" => "go_modules",
        "gradle" => "gradle",
        "maven" => "maven",
        "maven_osv" => "maven_osv",
        "mix" => "hex",
        "nuget" => "nuget",
        "npm" => "npm_and_yarn",
        "pip" => "pip",
        "pub" => "pub",
        "swift" => "swift",
        "terraform" => "terraform"
      }.freeze, T::Hash[String, String])

      sig { params(cfg: T.nilable(T::Hash[Symbol, T.untyped])).returns(T::Array[IgnoreCondition]) }
      def ignore_conditions(cfg)
        ignores = cfg&.dig(:ignore) || []
        ignores.map do |ic|
          IgnoreCondition.new(
            dependency_name: ic[:"dependency-name"],
            versions: ic[:versions],
            update_types: ic[:"update-types"]
          )
        end
      end

      sig do
        params(cfg: T.nilable(T::Hash[Symbol, T.untyped])).returns(UpdateConfig::CommitMessageOptions)
      end
      def commit_message_options(cfg)
        commit_message = cfg&.dig(:"commit-message") || {}
        UpdateConfig::CommitMessageOptions.new(
          prefix: commit_message[:prefix],
          prefix_development: commit_message[:"prefix-development"] || commit_message[:prefix],
          include: commit_message[:include]
        )
      end
    end
  end
end
