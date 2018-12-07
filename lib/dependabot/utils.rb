# frozen_string_literal: true

require "dependabot/utils/dotnet/version"
require "dependabot/utils/elixir/version"
require "dependabot/utils/java/version"
require "dependabot/utils/java_script/version"
require "dependabot/utils/php/version"
require "dependabot/utils/rust/version"
require "dependabot/utils/go/version"
require "dependabot/utils/elm/version"

require "dependabot/utils/dotnet/requirement"
require "dependabot/utils/elixir/requirement"
require "dependabot/utils/java/requirement"
require "dependabot/utils/java_script/requirement"
require "dependabot/utils/php/requirement"
require "dependabot/utils/ruby/requirement"
require "dependabot/utils/rust/requirement"
require "dependabot/utils/go/requirement"
require "dependabot/utils/elm/requirement"

# TODO: in due course, these "registries" should live in a wrapper gem, not
#       dependabot-core.
module Dependabot
  module Utils
    @version_classes = {
      "bundler" => Gem::Version,
      "submodules" => Gem::Version,
      "docker" => Gem::Version,
      "nuget" => Utils::Dotnet::Version,
      "maven" => Utils::Java::Version,
      "gradle" => Utils::Java::Version,
      "npm_and_yarn" => Utils::JavaScript::Version,
      "composer" => Utils::Php::Version,
      "hex" => Utils::Elixir::Version,
      "cargo" => Utils::Rust::Version,
      "dep" => Utils::Go::Version,
      "go_modules" => Utils::Go::Version,
      "elm-package" => Utils::Elm::Version
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
      "nuget" => Utils::Dotnet::Requirement,
      "maven" => Utils::Java::Requirement,
      "gradle" => Utils::Java::Requirement,
      "npm_and_yarn" => Utils::JavaScript::Requirement,
      "composer" => Utils::Php::Requirement,
      "hex" => Utils::Elixir::Requirement,
      "cargo" => Utils::Rust::Requirement,
      "dep" => Utils::Go::Requirement,
      "go_modules" => Utils::Go::Requirement,
      "elm-package" => Utils::Elm::Requirement
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
