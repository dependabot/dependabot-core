# frozen_string_literal: true

require "dependabot/file_updaters/ruby/bundler"

module Dependabot
  module FileUpdaters
    @file_updaters = {
      "bundler" => FileUpdaters::Ruby::Bundler
    }

    def self.for_package_manager(package_manager)
      file_updater = @file_updaters[package_manager]
      return file_updater if file_updater

      raise "Unsupported package_manager #{package_manager}"
    end

    def self.register(package_manager, file_updater)
      @file_updaters[package_manager] = file_updater
    end
  end
end
