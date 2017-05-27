# frozen_string_literal: true
require "bump/update_checkers/ruby/bundler"
require "bump/update_checkers/python/pip"
require "bump/update_checkers/java_script/yarn"

module Bump
  module UpdateCheckers
    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler" then UpdateCheckers::Ruby::Bundler
      when "yarn" then UpdateCheckers::JavaScript::Yarn
      when "pip" then UpdateCheckers::Python::Pip
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
  end
end
