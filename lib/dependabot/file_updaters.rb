# frozen_string_literal: true

require "dependabot/file_updaters/ruby/bundler"
require "dependabot/file_updaters/python/pip"
require "dependabot/file_updaters/java_script/npm"
require "dependabot/file_updaters/java_script/yarn"
require "dependabot/file_updaters/php/composer"
require "dependabot/file_updaters/git/submodules"
require "dependabot/file_updaters/docker/docker"

module Dependabot
  module FileUpdaters
    # rubocop:disable Metrics/CyclomaticComplexity
    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler" then FileUpdaters::Ruby::Bundler
      when "npm" then FileUpdaters::JavaScript::Npm
      when "yarn" then FileUpdaters::JavaScript::Yarn
      when "pip" then FileUpdaters::Python::Pip
      when "composer" then FileUpdaters::Php::Composer
      when "submodules" then FileUpdaters::Git::Submodules
      when "docker" then FileUpdaters::Docker::Docker
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity
  end
end
