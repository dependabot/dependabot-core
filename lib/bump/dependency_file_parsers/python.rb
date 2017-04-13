# frozen_string_literal: true
require "bump/dependency"
require "bump/python_helpers"

module Bump
  module DependencyFileParsers
    class Python
      def initialize(dependency_files:)
        @requirements = dependency_files.find { |f| f.name == "requirements.txt" }
        raise "No requirements.txt!" unless @requirements
      end

      def parse
        PythonHelpers.
          parse_requirements(@requirements.content).
          map { |dep| Dependency.new(name: dep[0], version: dep[1]) }
      end
    end
  end
end
