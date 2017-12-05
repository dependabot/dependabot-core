# frozen_string_literal: true

require "dependabot/file_fetchers/ruby/bundler"
require "dependabot/file_fetchers/python/pip"
require "dependabot/file_fetchers/java_script/npm_and_yarn"
require "dependabot/file_fetchers/php/composer"
require "dependabot/file_fetchers/git/submodules"
require "dependabot/file_fetchers/docker/docker"

module Dependabot
  module FileFetchers
    # rubocop:disable Metrics/CyclomaticComplexity
    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler" then FileFetchers::Ruby::Bundler
      when "npm_and_yarn" then FileFetchers::JavaScript::NpmAndYarn
      when "pip" then FileFetchers::Python::Pip
      when "composer" then FileFetchers::Php::Composer
      when "submodules" then FileFetchers::Git::Submodules
      when "docker" then FileFetchers::Docker::Docker
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity
  end
end
