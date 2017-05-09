# frozen_string_literal: true
require "bump/dependency_file_fetchers/ruby"
require "bump/dependency_file_fetchers/python"
require "bump/dependency_file_fetchers/javascript"

module Bump
  module DependencyFileFetchers
    def self.for_language(language)
      case language
      when "ruby" then DependencyFileFetchers::Ruby
      when "javascript" then DependencyFileFetchers::Javascript
      when "python" then DependencyFileFetchers::Python
      else raise "Invalid language #{language}"
      end
    end
  end
end
