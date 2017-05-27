# frozen_string_literal: true
require "bump/dependency_metadata_finders/ruby/bundler"
require "bump/dependency_metadata_finders/python/pip"
require "bump/dependency_metadata_finders/java_script/yarn"

module Bump
  module DependencyMetadataFinders
    def self.for_package_manager(package_manager)
      case package_manager
      when "bundler" then DependencyMetadataFinders::Ruby::Bundler
      when "yarn" then DependencyMetadataFinders::JavaScript::Yarn
      when "pip" then DependencyMetadataFinders::Python::Pip
      else raise "Unsupported package_manager #{package_manager}"
      end
    end
  end
end
