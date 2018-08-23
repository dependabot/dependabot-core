# frozen_string_literal: true

require "dependabot/file_updaters/ruby/bundler"
require "dependabot/file_updaters/python/pip"
require "dependabot/file_updaters/java_script/npm_and_yarn"
require "dependabot/file_updaters/java/maven"
require "dependabot/file_updaters/java/gradle"
require "dependabot/file_updaters/php/composer"
require "dependabot/file_updaters/git/submodules"
require "dependabot/file_updaters/docker/docker"
require "dependabot/file_updaters/elixir/hex"
require "dependabot/file_updaters/rust/cargo"
require "dependabot/file_updaters/dotnet/nuget"
require "dependabot/file_updaters/go/dep"
require "dependabot/file_updaters/elm/elm_package"
require "dependabot/file_updaters/terraform/terraform"

module Dependabot
  module FileUpdaters
    # rubocop:disable Metrics/CyclomaticComplexity
    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler" then FileUpdaters::Ruby::Bundler
      when "npm_and_yarn" then FileUpdaters::JavaScript::NpmAndYarn
      when "maven" then FileUpdaters::Java::Maven
      when "gradle" then FileUpdaters::Java::Gradle
      when "pip" then FileUpdaters::Python::Pip
      when "composer" then FileUpdaters::Php::Composer
      when "submodules" then FileUpdaters::Git::Submodules
      when "docker" then FileUpdaters::Docker::Docker
      when "hex" then FileUpdaters::Elixir::Hex
      when "cargo" then FileUpdaters::Rust::Cargo
      when "nuget" then FileUpdaters::Dotnet::Nuget
      when "dep" then FileUpdaters::Go::Dep
      when "elm-package" then FileUpdaters::Elm::ElmPackage
      when "terraform" then FileUpdaters::Terraform::Terraform
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity
  end
end
