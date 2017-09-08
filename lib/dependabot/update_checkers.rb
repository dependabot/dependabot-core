# frozen_string_literal: true
require "dependabot/update_checkers/ruby/bundler"
require "dependabot/update_checkers/cocoa/cocoa_pods"
require "dependabot/update_checkers/python/pip"
require "dependabot/update_checkers/java_script/yarn"
require "dependabot/update_checkers/php/composer"
require "dependabot/update_checkers/git/submodules"

module Dependabot
  module UpdateCheckers
    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler" then UpdateCheckers::Ruby::Bundler
      when "cocoapods" then UpdateCheckers::Cocoa::CocoaPods
      when "yarn" then UpdateCheckers::JavaScript::Yarn
      when "pip" then UpdateCheckers::Python::Pip
      when "composer" then UpdateCheckers::Php::Composer
      when "submodules" then UpdateCheckers::Git::Submodules
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
  end
end
