# frozen_string_literal: true
require "bump/dependency_file_fetchers/ruby/bundler"
require "bump/dependency_file_fetchers/python/pip"
require "bump/dependency_file_fetchers/java_script/yarn"

module Bump
  module DependencyFileFetchers
    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler" then DependencyFileFetchers::Ruby::Bundler
      when "yarn" then DependencyFileFetchers::JavaScript::Yarn
      when "pip" then DependencyFileFetchers::Python::Pip
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
  end
end
