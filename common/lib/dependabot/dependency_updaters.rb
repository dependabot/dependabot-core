# frozen_string_literal: true

module Dependabot
  module DependencyUpdaters
    @dependency_updaters = {}

    def self.for_package_manager(package_manager)
      dependency_updater = @dependency_updaters[package_manager]
      return dependency_updater if dependency_updater

      raise "Unsupported package_manager #{package_manager}"
    end

    def self.register(package_manager, dependency_updater)
      @dependency_updaters[package_manager] = dependency_updater
    end
  end
end
