# frozen_string_literal: true

require "dependabot/file_parsers/ruby/bundler"
require "dependabot/file_parsers/python/pip"
require "dependabot/file_parsers/java_script/yarn"
require "dependabot/file_parsers/php/composer"
require "dependabot/file_parsers/git/submodules"
require "dependabot/file_parsers/docker/docker"

module Dependabot
  module FileParsers
    # rubocop:disable Metrics/CyclomaticComplexity
    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler" then FileParsers::Ruby::Bundler
      when "yarn" then FileParsers::JavaScript::Yarn
      when "pip" then FileParsers::Python::Pip
      when "composer" then FileParsers::Php::Composer
      when "submodules" then FileParsers::Git::Submodules
      when "docker" then FileParsers::Docker::Docker
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
    # rubocop:enable Metrics/CyclomaticComplexity
  end
end
