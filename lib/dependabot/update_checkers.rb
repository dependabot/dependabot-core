# frozen_string_literal: true

require "dependabot/update_checkers/ruby/bundler"
require "dependabot/update_checkers/java_script/npm_and_yarn"

module Dependabot
  module UpdateCheckers
    @update_checkers = {
      "bundler" => UpdateCheckers::Ruby::Bundler,
      "npm_and_yarn" => UpdateCheckers::JavaScript::NpmAndYarn
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
