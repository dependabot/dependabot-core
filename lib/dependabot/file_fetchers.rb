# frozen_string_literal: true

require "dependabot/file_fetchers/ruby/bundler"
require "dependabot/file_fetchers/python/pip"
require "dependabot/file_fetchers/java_script/npm_and_yarn"
require "dependabot/file_fetchers/java/maven"
require "dependabot/file_fetchers/java/gradle"
require "dependabot/file_fetchers/php/composer"
require "dependabot/file_fetchers/git/submodules"
require "dependabot/file_fetchers/docker/docker"
require "dependabot/file_fetchers/elixir/hex"
require "dependabot/file_fetchers/rust/cargo"
require "dependabot/file_fetchers/dotnet/nuget"

module Dependabot
  module FileFetchers
    # rubocop:disable Metrics/CyclomaticComplexity
    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler" then FileFetchers::Ruby::Bundler
      when "npm_and_yarn" then FileFetchers::JavaScript::NpmAndYarn
      when "maven" then FileFetchers::Java::Maven
      when "gradle" then FileFetchers::Java::Gradle
      when "pip" then FileFetchers::Python::Pip
      when "composer" then FileFetchers::Php::Composer
      when "submodules" then FileFetchers::Git::Submodules
      when "docker" then FileFetchers::Docker::Docker
      when "hex" then FileFetchers::Elixir::Hex
      when "cargo" then FileFetchers::Rust::Cargo
      when "nuget" then FileFetchers::Dotnet::Nuget
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity
  end
end
