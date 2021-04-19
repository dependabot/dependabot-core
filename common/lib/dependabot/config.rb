# frozen_string_literal: true

module Dependabot
  module ConfigFile
    class InvalidConfigError < StandardError; end

    module Interval
      DAILY = "daily"
      WEEKLY = "weekly"
      MONTHLY = "monthly"
    end

    # Configuration for every ecosystem
    class Config
      attr_reader :updates, :registries

      def initialize(updates:, registries: nil)
        @updates = updates || []
        @registries = registries || []
      end

      def update_config(package_manager, directory: nil)
        dir = directory || "/"
        package_ecosystem = PACKAGE_MANAGER_LOOKUP.invert.fetch(package_manager)
        cfg = updates.find { |u| u[:"package-ecosystem"] == package_ecosystem && u[:directory] == dir }
        UpdateConfig.new(cfg)
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
    end

    # Configuration for a single ecosystem
    class UpdateConfig
      def initialize(config)
        @config = config || {}
      end

      def ignored_versions_for(dep)
        return [] unless @config[:ignore]

        @config[:ignore].
          select { |ic| ic[:"dependency-name"] == dep.name }. # FIXME: wildcard support
          map { |ic| ic[:versions] }.
          flatten
      end

      def interval
        return unless @config[:schedule]
        return unless @config[:schedule][:interval]

        interval = @config[:schedule][:interval]
        case interval.downcase
        when Interval::DAILY, Interval::WEEKLY, Interval::MONTHLY
          interval.downcase
        else
          raise InvalidConfigError, "unknown interval: #{interval}"
        end
      end
    end

    # Parse the YAML config file
    def self.parse(config)
      parsed = YAML.safe_load(config, symbolize_names: true)
      version = parsed[:version]
      raise InvalidConfigError, "invalid version #{version}" if version && version != 2

      Config.new(updates: parsed[:updates], registries: parsed[:registries])
    end
  end
end
