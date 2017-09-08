# frozen_string_literal: true
require "dependabot/file_updaters/ruby/bundler"
require "dependabot/file_updaters/cocoa/cocoa_pods"
require "dependabot/file_updaters/python/pip"
require "dependabot/file_updaters/java_script/yarn"
require "dependabot/file_updaters/php/composer"
require "dependabot/file_updaters/git/submodules"

module Dependabot
  module FileUpdaters
    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler" then FileUpdaters::Ruby::Bundler
      when "cocoa" then FileUpdaters::Cocoa::CocoaPods
      when "yarn" then FileUpdaters::JavaScript::Yarn
      when "pip" then FileUpdaters::Python::Pip
      when "composer" then FileUpdaters::Php::Composer
      when "submodules" then FileUpdaters::Git::Submodules
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
  end
end
