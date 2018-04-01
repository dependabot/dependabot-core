# frozen_string_literal: true

require "dependabot/update_checkers/python/pip/requirement"
require "dependabot/update_checkers/java_script/npm_and_yarn/requirement"
require "dependabot/update_checkers/php/composer/requirement"
require "dependabot/update_checkers/elixir/hex/requirement"
require "dependabot/update_checkers/rust/cargo/requirement"

module Dependabot
  module Requirement
    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler", "maven", "submodules", "docker" then Gem::Requirement
      when "npm_and_yarn"
        UpdateCheckers::JavaScript::NpmAndYarn::Requirement
      when "pip" then UpdateCheckers::Python::Pip::Requirement
      when "composer" then UpdateCheckers::Php::Composer::Requirement
      when "hex" then UpdateCheckers::Elixir::Hex::Requirement
      when "cargo" then UpdateCheckers::Rust::Cargo::Requirement
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
  end
end
