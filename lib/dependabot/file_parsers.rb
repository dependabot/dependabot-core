# frozen_string_literal: true

require "dependabot/file_parsers/ruby/bundler"
require "dependabot/file_parsers/python/pip"
require "dependabot/file_parsers/java_script/npm_and_yarn"
require "dependabot/file_parsers/python/pipfile"
require "dependabot/file_parsers/java/maven"
require "dependabot/file_parsers/php/composer"
require "dependabot/file_parsers/git/submodules"
require "dependabot/file_parsers/docker/docker"
require "dependabot/file_parsers/elixir/hex"

module Dependabot
  module FileParsers
    # rubocop:disable Metrics/CyclomaticComplexity
    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler" then FileParsers::Ruby::Bundler
      when "npm_and_yarn" then FileParsers::JavaScript::NpmAndYarn
      when "maven" then FileParsers::Java::Maven
      when "pip" then FileParsers::Python::Pip
      when "pipfile" then FileParsers::Python::Pipfile
      when "composer" then FileParsers::Php::Composer
      when "submodules" then FileParsers::Git::Submodules
      when "docker" then FileParsers::Docker::Docker
      when "hex" then FileParsers::Elixir::Hex
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity
  end
end
