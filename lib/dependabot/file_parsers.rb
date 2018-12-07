# frozen_string_literal: true

require "dependabot/file_parsers/ruby/bundler"
require "dependabot/file_parsers/python/pip"
require "dependabot/file_parsers/java_script/npm_and_yarn"
require "dependabot/file_parsers/java/maven"
require "dependabot/file_parsers/java/gradle"
require "dependabot/file_parsers/php/composer"
require "dependabot/file_parsers/git/submodules"
require "dependabot/file_parsers/elixir/hex"
require "dependabot/file_parsers/rust/cargo"
require "dependabot/file_parsers/dotnet/nuget"
require "dependabot/file_parsers/go/dep"
require "dependabot/file_parsers/go/modules"
require "dependabot/file_parsers/elm/elm_package"

module Dependabot
  module FileParsers
    @file_parsers = {
      "bundler" => FileParsers::Ruby::Bundler,
      "npm_and_yarn" => FileParsers::JavaScript::NpmAndYarn,
      "maven" => FileParsers::Java::Maven,
      "gradle" => FileParsers::Java::Gradle,
      "pip" => FileParsers::Python::Pip,
      "composer" => FileParsers::Php::Composer,
      "submodules" => FileParsers::Git::Submodules,
      "hex" => FileParsers::Elixir::Hex,
      "cargo" => FileParsers::Rust::Cargo,
      "nuget" => FileParsers::Dotnet::Nuget,
      "dep" => FileParsers::Go::Dep,
      "go_modules" => FileParsers::Go::Modules,
      "elm-package" => FileParsers::Elm::ElmPackage
    }

    def self.for_package_manager(package_manager)
      file_parser = @file_parsers[package_manager]
      return file_parser if file_parser

      raise "Unsupported package_manager #{package_manager}"
    end

    def self.register(package_manager, file_parser)
      @file_parsers[package_manager] = file_parser
    end
  end
end
