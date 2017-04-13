# frozen_string_literal: true
require "bump/dependency_metadata_finders/ruby"
require "bump/dependency_metadata_finders/python"
require "bump/dependency_metadata_finders/node"

module Bump
  module DependencyMetadataFinders
    def self.for_language(language)
      case language
      when "ruby" then DependencyMetadataFinders::Ruby
      when "node" then DependencyMetadataFinders::Node
      when "python" then DependencyMetadataFinders::Python
      else raise "Invalid language #{language}"
      end
    end
  end
end
