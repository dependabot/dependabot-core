# frozen_string_literal: true

require "dependabot/file_updaters/ruby/bundler"
require "dependabot/file_updaters/java_script/npm_and_yarn"
require "dependabot/file_updaters/php/composer"
require "dependabot/file_updaters/elixir/hex"
require "dependabot/file_updaters/go/dep"

module Dependabot
  module FileUpdaters
    @file_updaters = {
      "bundler" => FileUpdaters::Ruby::Bundler,
      "npm_and_yarn" => FileUpdaters::JavaScript::NpmAndYarn,
      "composer" => FileUpdaters::Php::Composer,
      "hex" => FileUpdaters::Elixir::Hex,
      "dep" => FileUpdaters::Go::Dep
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
