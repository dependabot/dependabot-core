# frozen_string_literal: true
require "bump/dependency_file_fetchers/ruby"
require "bump/dependency_file_fetchers/python"
require "bump/dependency_file_fetchers/java_script"
require "bump/dependency_file_fetchers/cocoa"

module Bump
  module DependencyFileFetchers
    def self.for_language(language)
      case language
      when "ruby" then DependencyFileFetchers::Ruby
      when "javascript" then DependencyFileFetchers::JavaScript
      when "python" then DependencyFileFetchers::Python
      when "cocoa" then DependencyFileFetchers::Cocoa
      else raise "Invalid language #{language}"
      end
    end
  end
end
