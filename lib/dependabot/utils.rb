# frozen_string_literal: true

require "dependabot/utils/elixir/version"
require "dependabot/utils/java_script/version"
require "dependabot/utils/php/version"
require "dependabot/utils/go/version"

require "dependabot/utils/elixir/requirement"
require "dependabot/utils/java_script/requirement"
require "dependabot/utils/php/requirement"
require "dependabot/utils/ruby/requirement"
require "dependabot/utils/go/requirement"

# TODO: in due course, these "registries" should live in a wrapper gem, not
#       dependabot-core.
module Dependabot
  module Utils
    @version_classes = {
      "bundler" => Gem::Version,
      "submodules" => Gem::Version,
      "docker" => Gem::Version,
      "npm_and_yarn" => Utils::JavaScript::Version,
      "composer" => Utils::Php::Version,
      "hex" => Utils::Elixir::Version,
      "dep" => Utils::Go::Version
    }

    def self.version_class_for_package_manager(package_manager)
      version_class = @version_classes[package_manager]
      return version_class if version_class

      raise "Unsupported package_manager #{package_manager}"
    end

    def self.register_version_class(package_manager, version_class)
      @version_classes[package_manager] = version_class
    end

    @requirement_classes = {
      "bundler" => Utils::Ruby::Requirement,
      "submodules" => Utils::Ruby::Requirement,
      "docker" => Utils::Ruby::Requirement,
      "npm_and_yarn" => Utils::JavaScript::Requirement,
      "composer" => Utils::Php::Requirement,
      "hex" => Utils::Elixir::Requirement,
      "dep" => Utils::Go::Requirement
    }

    def self.requirement_class_for_package_manager(package_manager)
      requirement_class = @requirement_classes[package_manager]
      return requirement_class if requirement_class

      raise "Unsupported package_manager #{package_manager}"
    end

    def self.register_requirement_class(package_manager, requirement_class)
      @requirement_classes[package_manager] = requirement_class
    end
  end
end
