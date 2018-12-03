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
require "dependabot/file_updaters/go/modules"
require "dependabot/file_updaters/elm/elm_package"

module Dependabot
  module FileUpdaters
    @file_updaters = {
      "bundler" => FileUpdaters::Ruby::Bundler,
      "npm_and_yarn" => FileUpdaters::JavaScript::NpmAndYarn,
      "maven" => FileUpdaters::Java::Maven,
      "gradle" => FileUpdaters::Java::Gradle,
      "pip" => FileUpdaters::Python::Pip,
      "composer" => FileUpdaters::Php::Composer,
      "submodules" => FileUpdaters::Git::Submodules,
      "docker" => FileUpdaters::Docker::Docker,
      "hex" => FileUpdaters::Elixir::Hex,
      "cargo" => FileUpdaters::Rust::Cargo,
      "nuget" => FileUpdaters::Dotnet::Nuget,
      "dep" => FileUpdaters::Go::Dep,
      "go_modules" => FileUpdaters::Go::Modules,
      "elm-package" => FileUpdaters::Elm::ElmPackage
    }

    def self.for_package_manager(package_manager)
      file_updater = @file_updaters[package_manager]
      return file_updater if file_updater

      raise "Unsupported package_manager #{package_manager}"
    end

    def self.register(package_manager, file_updater)
      @file_updaters[package_manager] = file_updater
    end
  end
end
