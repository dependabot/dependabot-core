# frozen_string_literal: true

require "dependabot/update_checkers/ruby/bundler"
require "dependabot/update_checkers/python/pip"
require "dependabot/update_checkers/java_script/npm_and_yarn"
require "dependabot/update_checkers/java/maven"
require "dependabot/update_checkers/java/gradle"
require "dependabot/update_checkers/php/composer"
require "dependabot/update_checkers/git/submodules"
require "dependabot/update_checkers/docker/docker"
require "dependabot/update_checkers/elixir/hex"
require "dependabot/update_checkers/rust/cargo"
require "dependabot/update_checkers/dotnet/nuget"
require "dependabot/update_checkers/go/dep"
require "dependabot/update_checkers/elm/elm_package"
require "dependabot/update_checkers/terraform/terraform"

module Dependabot
  module UpdateCheckers
    # rubocop:disable Metrics/CyclomaticComplexity
    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler" then UpdateCheckers::Ruby::Bundler
      when "npm_and_yarn" then UpdateCheckers::JavaScript::NpmAndYarn
      when "maven" then UpdateCheckers::Java::Maven
      when "gradle" then UpdateCheckers::Java::Gradle
      when "pip" then UpdateCheckers::Python::Pip
      when "composer" then UpdateCheckers::Php::Composer
      when "submodules" then UpdateCheckers::Git::Submodules
      when "docker" then UpdateCheckers::Docker::Docker
      when "hex" then UpdateCheckers::Elixir::Hex
      when "cargo" then UpdateCheckers::Rust::Cargo
      when "nuget" then UpdateCheckers::Dotnet::Nuget
      when "dep" then UpdateCheckers::Go::Dep
      when "elm-package" then UpdateCheckers::Elm::ElmPackage
      when "terraform" then UpdateCheckers::Terraform::Terraform
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity
  end
end
