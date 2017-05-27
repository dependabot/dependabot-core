# frozen_string_literal: true
require "bump/dependency_file_updaters/ruby/bundler"
require "bump/dependency_file_updaters/python/pip"
require "bump/dependency_file_updaters/java_script/yarn"

module Bump
  module DependencyFileUpdaters
    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler" then DependencyFileUpdaters::Ruby::Bundler
      when "yarn" then DependencyFileUpdaters::JavaScript::Yarn
      when "pip" then DependencyFileUpdaters::Python::Pip
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
  end
end
