# frozen_string_literal: true

require "dependabot/update_checkers/ruby/bundler"
require "dependabot/update_checkers/java_script/npm_and_yarn"
require "dependabot/update_checkers/java/maven"
require "dependabot/update_checkers/php/composer"
require "dependabot/update_checkers/elixir/hex"
require "dependabot/update_checkers/go/dep"
require "dependabot/update_checkers/go/modules"

module Dependabot
  module UpdateCheckers
    @update_checkers = {
      "bundler" => UpdateCheckers::Ruby::Bundler,
      "npm_and_yarn" => UpdateCheckers::JavaScript::NpmAndYarn,
      "maven" => UpdateCheckers::Java::Maven,
      "composer" => UpdateCheckers::Php::Composer,
      "hex" => UpdateCheckers::Elixir::Hex,
      "dep" => UpdateCheckers::Go::Dep,
      "go_modules" => UpdateCheckers::Go::Modules
    }

    def self.for_package_manager(package_manager)
      update_checker = @update_checkers[package_manager]
      return update_checker if update_checker

      raise "Unsupported package_manager #{package_manager}"
    end

    def self.register(package_manager, update_checker)
      @update_checkers[package_manager] = update_checker
    end
  end
end
