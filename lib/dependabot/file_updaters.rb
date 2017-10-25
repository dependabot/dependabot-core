# frozen_string_literal: true

require "dependabot/file_updaters/ruby/bundler"
require "dependabot/file_updaters/python/pip"
require "dependabot/file_updaters/java_script/npm_and_yarn"
require "dependabot/file_updaters/python/pipfile"
require "dependabot/file_updaters/php/composer"
require "dependabot/file_updaters/git/submodules"
require "dependabot/file_updaters/docker/docker"

module Dependabot
  module FileUpdaters
    # rubocop:disable Metrics/CyclomaticComplexity
    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler" then FileUpdaters::Ruby::Bundler
      when "npm_and_yarn" then FileUpdaters::JavaScript::NpmAndYarn
      when "pip" then FileUpdaters::Python::Pip
      when "pipfile" then FileUpdaters::Python::Pipfile
      when "composer" then FileUpdaters::Php::Composer
      when "submodules" then FileUpdaters::Git::Submodules
      when "docker" then FileUpdaters::Docker::Docker
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity
  end
end
