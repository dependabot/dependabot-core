# frozen_string_literal: true
require "bump/dependency_file_parsers/ruby"
require "bump/dependency_file_parsers/python"
require "bump/dependency_file_parsers/javascript"

module Bump
  module DependencyFileParsers
    def self.for_language(language)
      case language
      when "ruby" then DependencyFileParsers::Ruby
      when "javascript" then DependencyFileParsers::Javascript
      when "python" then DependencyFileParsers::Python
      else raise "Invalid language #{language}"
      end
    end
  end
end
