# frozen_string_literal: true

require "dependabot/utils/python/version"
require "dependabot/utils/elixir/version"
require "dependabot/utils/java/version"
require "dependabot/utils/java_script/version"
require "dependabot/utils/php/version"
require "dependabot/utils/rust/version"

module Dependabot
  module Utils
    # rubocop:disable Metrics/CyclomaticComplexity
    def self.version_class_for_package_manager(package_manager)
      case package_manager
      when "bundler", "submodules", "docker" then Gem::Version
      when "maven" then Utils::Java::Version
      when "npm_and_yarn" then Utils::JavaScript::Version
      when "pip" then Utils::Python::Version
      when "composer" then Utils::Php::Version
      when "hex" then Utils::Elixir::Version
      when "cargo" then UpdateCheckers::Rust::Cargo::Version
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity
  end
end
