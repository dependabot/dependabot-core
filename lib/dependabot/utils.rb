# frozen_string_literal: true

require "dependabot/utils/dotnet/version"
require "dependabot/utils/elixir/version"
require "dependabot/utils/java/version"
require "dependabot/utils/java_script/version"
require "dependabot/utils/php/version"
require "dependabot/utils/python/version"
require "dependabot/utils/rust/version"
require "dependabot/utils/go/version"
require "dependabot/utils/elm/version"
require "dependabot/utils/terraform/version"

require "dependabot/utils/dotnet/requirement"
require "dependabot/utils/elixir/requirement"
require "dependabot/utils/java/requirement"
require "dependabot/utils/java_script/requirement"
require "dependabot/utils/php/requirement"
require "dependabot/utils/python/requirement"
require "dependabot/utils/ruby/requirement"
require "dependabot/utils/rust/requirement"
require "dependabot/utils/go/requirement"
require "dependabot/utils/elm/requirement"

# rubocop:disable Metrics/CyclomaticComplexity
module Dependabot
  module Utils
    def self.version_class_for_package_manager(package_manager)
      case package_manager
      when "bundler", "submodules", "docker" then Gem::Version
      when "nuget" then Utils::Dotnet::Version
      when "maven" then Utils::Java::Version
      when "gradle" then Utils::Java::Version
      when "npm_and_yarn" then Utils::JavaScript::Version
      when "pip" then Utils::Python::Version
      when "composer" then Utils::Php::Version
      when "hex" then Utils::Elixir::Version
      when "cargo" then Utils::Rust::Version
      when "dep" then Utils::Go::Version
      when "go_modules" then Utils::Go::Version
      when "elm-package" then Utils::Elm::Version
      when "terraform" then Utils::Terraform::Version
      else raise "Unsupported package_manager #{package_manager}"
      end
    end

    @requirement_classes = {
      "bundler" => Utils::Ruby::Requirement,
      "submodules" => Utils::Ruby::Requirement,
      "docker" => Utils::Ruby::Requirement,
      "nuget" => Utils::Dotnet::Requirement,
      "maven" => Utils::Java::Requirement,
      "gradle" => Utils::Java::Requirement,
      "npm_and_yarn" => Utils::JavaScript::Requirement,
      "pip" => Utils::Python::Requirement,
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
# rubocop:enable Metrics/CyclomaticComplexity
