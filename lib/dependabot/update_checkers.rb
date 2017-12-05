# frozen_string_literal: true

require "dependabot/update_checkers/ruby/bundler"
require "dependabot/update_checkers/python/pip"
require "dependabot/update_checkers/java_script/npm_and_yarn"
require "dependabot/update_checkers/php/composer"
require "dependabot/update_checkers/git/submodules"
require "dependabot/update_checkers/docker/docker"

module Dependabot
  module UpdateCheckers
    # rubocop:disable Metrics/CyclomaticComplexity
    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler" then UpdateCheckers::Ruby::Bundler
      when "npm", "yarn", "npm_and_yarn"
        UpdateCheckers::JavaScript::NpmAndYarn
      when "pip" then UpdateCheckers::Python::Pip
      when "composer" then UpdateCheckers::Php::Composer
      when "submodules" then UpdateCheckers::Git::Submodules
      when "docker" then UpdateCheckers::Docker::Docker
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity
  end
end
