# frozen_string_literal: true

require "dependabot/config/update_config"

module Dependabot
  module Config
    # Configuration for the repository, a parsed dependabot.yaml.
    class File
      attr_reader :updates, :registries

      def initialize(updates:, registries: nil)
        @updates = updates || []
        @registries = registries || []
      end

      def update_config(package_manager, directory: nil, target_branch: nil)
        dir = directory || "/"
        package_ecosystem = PACKAGE_MANAGER_LOOKUP.invert.fetch(package_manager)
        cfg = updates.find do |u|
          u[:"package-ecosystem"] == package_ecosystem && u[:directory] == dir &&
            (target_branch.nil? || u[:"target-branch"] == target_branch)
        end
        Dependabot::Config::UpdateConfig.new(
          cfg,
          commit_message_options: commit_message_options(cfg)
        )
      end

      PACKAGE_MANAGER_LOOKUP = {
        "bundler" => "bundler",
        "cargo" => "cargo",
        "composer" => "composer",
        "docker" => "docker",
        "elm" => "elm",
        "github-actions" => "github_actions",
        "gitsubmodule" => "submodules",
        "gomod" => "go_modules",
        "gradle" => "gradle",
        "maven" => "maven",
        "mix" => "hex",
        "nuget" => "nuget",
        "npm" => "npm_and_yarn",
        "pip" => "pip",
        "terraform" => "terraform"
      }.freeze

      # Parse the YAML config file
      def self.parse(config)
        parsed = YAML.safe_load(config, symbolize_names: true)
        version = parsed[:version]
        raise InvalidConfigError, "invalid version #{version}" if version && version != 2

        File.new(updates: parsed[:updates], registries: parsed[:registries])
      end

      private

      def commit_message_options(cfg)
        commit_message = cfg&.dig(:"commit-message") || {}
        Dependabot::Config::UpdateConfig::CommitMessageOptions.new(
          prefix: commit_message[:prefix],
          prefix_development: commit_message[:"prefix-development"],
          include: commit_message[:include]
        )
      end
    end
  end
end
