# frozen_string_literal: true

require "dependabot/file_fetchers/ruby/bundler"
require "dependabot/file_fetchers/python/pip"
require "dependabot/file_fetchers/java_script/npm_and_yarn"
require "dependabot/file_fetchers/java/maven"
require "dependabot/file_fetchers/java/gradle"
require "dependabot/file_fetchers/php/composer"
require "dependabot/file_fetchers/git/submodules"
require "dependabot/file_fetchers/elixir/hex"
require "dependabot/file_fetchers/rust/cargo"
require "dependabot/file_fetchers/dotnet/nuget"
require "dependabot/file_fetchers/go/dep"
require "dependabot/file_fetchers/go/modules"
require "dependabot/file_fetchers/elm/elm_package"

module Dependabot
  module FileFetchers
    @file_fetchers = {
      "bundler" => FileFetchers::Ruby::Bundler,
      "npm_and_yarn" => FileFetchers::JavaScript::NpmAndYarn,
      "maven" => FileFetchers::Java::Maven,
      "gradle" => FileFetchers::Java::Gradle,
      "pip" => FileFetchers::Python::Pip,
      "composer" => FileFetchers::Php::Composer,
      "submodules" => FileFetchers::Git::Submodules,
      "hex" => FileFetchers::Elixir::Hex,
      "cargo" => FileFetchers::Rust::Cargo,
      "nuget" => FileFetchers::Dotnet::Nuget,
      "dep" => FileFetchers::Go::Dep,
      "go_modules" => FileFetchers::Go::Modules,
      "elm-package" => FileFetchers::Elm::ElmPackage
    }

    def self.for_package_manager(package_manager)
      file_fetcher = @file_fetchers[package_manager]
      return file_fetcher if file_fetcher

      raise "Unsupported package_manager #{package_manager}"
    end

    def self.register(package_manager, file_fetcher)
      @file_fetchers[package_manager] = file_fetcher
    end
  end
end
