# frozen_string_literal: true
require "bump/file_updaters/ruby/bundler"
require "bump/file_updaters/python/pip"
require "bump/file_updaters/java_script/yarn"

module Bump
  module FileUpdaters
    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler" then FileUpdaters::Ruby::Bundler
      when "yarn" then FileUpdaters::JavaScript::Yarn
      when "pip" then FileUpdaters::Python::Pip
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
  end
end
