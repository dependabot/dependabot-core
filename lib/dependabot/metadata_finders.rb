# frozen_string_literal: true

require "dependabot/metadata_finders/ruby/bundler"
require "dependabot/metadata_finders/python/pip"
require "dependabot/metadata_finders/java_script/yarn"
require "dependabot/metadata_finders/php/composer"
require "dependabot/metadata_finders/git/submodules"

module Dependabot
  module MetadataFinders
    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler" then MetadataFinders::Ruby::Bundler
      when "yarn" then MetadataFinders::JavaScript::Yarn
      when "pip" then MetadataFinders::Python::Pip
      when "composer" then MetadataFinders::Php::Composer
      when "submodules" then MetadataFinders::Git::Submodules
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
  end
end
