# frozen_string_literal: true
require "bump/dependency_metadata_finders/ruby"
require "bump/dependency_metadata_finders/python"
require "bump/dependency_metadata_finders/java_script"
require "bump/dependency_metadata_finders/cocoa"

module Bump
  module DependencyMetadataFinders
    def self.for_language(language)
      case language
      when "ruby" then DependencyMetadataFinders::Ruby
      when "javascript" then DependencyMetadataFinders::JavaScript
      when "python" then DependencyMetadataFinders::Python
      when "cocoa" then DependencyMetadataFinders::Cocoa
      else raise "Invalid language #{language}"
      end
    end
  end
end
