# frozen_string_literal: true

require "dependabot/file_fetchers/ruby/bundler"
require "dependabot/file_fetchers/java_script/npm_and_yarn"
require "dependabot/file_fetchers/php/composer"
require "dependabot/file_fetchers/elixir/hex"
require "dependabot/file_fetchers/go/dep"

module Dependabot
  module FileFetchers
    @file_fetchers = {
      "bundler" => FileFetchers::Ruby::Bundler,
      "npm_and_yarn" => FileFetchers::JavaScript::NpmAndYarn,
      "composer" => FileFetchers::Php::Composer,
      "hex" => FileFetchers::Elixir::Hex,
      "dep" => FileFetchers::Go::Dep
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
