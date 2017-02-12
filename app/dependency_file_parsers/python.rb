require "./app/dependency"
require "./lib/python_helpers"

module DependencyFileParsers
  class Python
    def initialize(dependency_files:)
      @requirements = dependency_files.find { |f| f.name == "requirements.txt" }
      raise "No requirements.txt!" unless @requirements
    end

    def parse
      PythonHelpers.requirements_parse(@requirements.content).
        each_with_object([]) do |pkg, deps|
        deps << Dependency.new(name: pkg[0],
                               version: pkg[1].match(/[\d\.]+/).to_s)
      end
    end
  end
end
