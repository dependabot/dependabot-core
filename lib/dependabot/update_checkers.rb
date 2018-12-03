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
require "dependabot/update_checkers/go/modules"
require "dependabot/update_checkers/elm/elm_package"

module Dependabot
  module UpdateCheckers
    @update_checkers = {
      "bundler" => UpdateCheckers::Ruby::Bundler,
      "npm_and_yarn" => UpdateCheckers::JavaScript::NpmAndYarn,
      "maven" => UpdateCheckers::Java::Maven,
      "gradle" => UpdateCheckers::Java::Gradle,
      "pip" => UpdateCheckers::Python::Pip,
      "composer" => UpdateCheckers::Php::Composer,
      "submodules" => UpdateCheckers::Git::Submodules,
      "docker" => UpdateCheckers::Docker::Docker,
      "hex" => UpdateCheckers::Elixir::Hex,
      "cargo" => UpdateCheckers::Rust::Cargo,
      "nuget" => UpdateCheckers::Dotnet::Nuget,
      "dep" => UpdateCheckers::Go::Dep,
      "go_modules" => UpdateCheckers::Go::Modules,
      "elm-package" => UpdateCheckers::Elm::ElmPackage
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
