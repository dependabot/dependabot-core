# frozen_string_literal: true

module Dependabot
  module ConfigFile
    class InvalidConfigError < StandardError; end

    PATH = ".github/dependabot.yaml"

    class Config
      attr_reader :updates, :registries
     
      def initialize(updates:, registries:)
        @updates = updates || []
        @registries = registries || []
      end
    end

    def self.parse(config)
      parsed = YAML.safe_load(config, symbolize_names: true)
      version = parsed[:version]
      raise InvalidConfigError, "invalid version #{version}" if version && version != 2
      return Config.new(updates: parsed[:updates], registries: parsed[:registries])
    end
  end
end
