# frozen_string_literal: true

module Dependabot
  module FileUpdaters
    @file_updaters = {}

    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler" then FileUpdaters::Ruby::Bundler
      when "cocoapods" then FileUpdaters::Cocoa::CocoaPods
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
      when "go_modules" then FileUpdaters::Go::Modules
      when "elm-package" then FileUpdaters::Elm::ElmPackage
      when "terraform" then FileUpdaters::Terraform::Terraform
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity
  end
end
