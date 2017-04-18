# frozen_string_literal: true
require "bump/dependency_file_updaters/ruby"
require "bump/dependency_file_updaters/python"
require "bump/dependency_file_updaters/node"

module Bump
  module DependencyFileUpdaters
    def self.for_language(language)
      case language
      when "ruby" then DependencyFileUpdaters::Ruby
      when "node" then DependencyFileUpdaters::Node
      when "python" then DependencyFileUpdaters::Python
      else raise "Invalid language #{language}"
      end
    end
  end
end
