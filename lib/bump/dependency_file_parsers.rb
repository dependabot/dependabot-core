# frozen_string_literal: true
require "bump/dependency_file_parsers/ruby/bundler"
require "bump/dependency_file_parsers/python/pip"
require "bump/dependency_file_parsers/java_script/yarn"

module Bump
  module DependencyFileParsers
    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler" then DependencyFileParsers::Ruby::Bundler
      when "yarn" then DependencyFileParsers::JavaScript::Yarn
      when "pip" then DependencyFileParsers::Python::Pip
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
  end
end
