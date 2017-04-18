# frozen_string_literal: true
require "bump/dependency_file_parsers/ruby"
require "bump/dependency_file_parsers/python"
require "bump/dependency_file_parsers/node"

module Bump
  module DependencyFileParsers
    def self.for_language(language)
      case language
      when "ruby" then DependencyFileParsers::Ruby
      when "node" then DependencyFileParsers::Node
      when "python" then DependencyFileParsers::Python
      else raise "Invalid language #{language}"
      end
    end
  end
end
