# frozen_string_literal: true

# These must be loaded first, or we get load order errors
require "dependabot/update_checkers/python/pip/requirement"
require "dependabot/update_checkers/elixir/hex/requirement"

require "dependabot/update_checkers/python/pip/version"
require "dependabot/update_checkers/java/maven/version"
require "dependabot/update_checkers/java_script/npm_and_yarn/version"
require "dependabot/update_checkers/php/composer/version"
require "dependabot/update_checkers/elixir/hex/version"
require "dependabot/update_checkers/rust/cargo/version"

module Dependabot
  module Version
    # rubocop:disable Metrics/CyclomaticComplexity
    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler", "submodules", "docker" then Gem::Version
      when "maven" then UpdateCheckers::Java::Maven::Version
      when "npm_and_yarn" then UpdateCheckers::JavaScript::NpmAndYarn::Version
      when "pip" then UpdateCheckers::Python::Pip::Version
      when "composer" then UpdateCheckers::Php::Composer::Version
      when "hex" then UpdateCheckers::Elixir::Hex::Version
      when "cargo" then UpdateCheckers::Rust::Cargo::Version
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity
  end
end
