# frozen_string_literal: true
require "bump/dependency_file_updaters/ruby"
require "bump/dependency_file_updaters/python"
require "bump/dependency_file_updaters/java_script"
require "bump/dependency_file_updaters/cocoa"

module Bump
  module DependencyFileUpdaters
    def self.for_language(language)
      case language
      when "ruby" then DependencyFileUpdaters::Ruby
      when "javascript" then DependencyFileUpdaters::JavaScript
      when "python" then DependencyFileUpdaters::Python
      when "cocoa" then DependencyFileUpdaters::Cocoa
      else raise "Invalid language #{language}"
      end
    end
  end
end
