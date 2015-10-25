require "gemnasium/parser"
require "./app/dependency_file"
require "bundler"
require "./lib/shared_helpers"

module DependencyFileUpdaters
  class Node
    attr_reader :package_json, :shrinkwrap, :dependency

    def initialize(dependency_files:, dependency:)
      @package_json = dependency_files.find { |f| f.name == "package.json" }
      @shrinkwrap = dependency_files.find do |file|
        file.name == "npm-shrinkwrap.json"
      end
      validate_files_are_present!

      @dependency = dependency
    end

    def updated_dependency_files
      [updated_package_json_file, updated_shrinkwrap]
    end

    def updated_package_json_file
      DependencyFile.new(
        name: "package.json",
        content: updated_package_json_content
      )
    end

    def updated_shrinkwrap
      DependencyFile.new(
        name: "npm-shrinkwrap.json",
        content: updated_shrinkwrap_content
      )
    end

    private

    def validate_files_are_present!
      raise "No package.json!" unless package_json
      raise "No npm-shrinkwrap.json!" unless shrinkwrap
    end

    def updated_package_json_content
      return @updated_package_json_content if @updated_package_json_content

      parsed_content = JSON.parse(@package_json.content)

      if parsed_content.fetch("dependencies", {})[dependency.name]
        parsed_content["dependencies"][dependency.name] = dependency.version
      end

      if parsed_content.fetch("devDependencies", {})[dependency.name]
        parsed_content["devDependencies"][dependency.name] = dependency.version
      end

      @updated_package_json_content =
        JSON.pretty_generate(parsed_content) + "\n"
    end

    def updated_shrinkwrap_content
      return @updated_shrinkwrap_content if @updated_shrinkwrap_content
      SharedHelpers.in_a_temporary_directory do |dir|
        File.write(File.join(dir, "package.json"), updated_package_json_content)
        `cd #{dir} && npm i --silent && npm shrinkwrap --silent`
        @updated_shrinkwrap_content =
          File.read(File.join(dir, "npm-shrinkwrap.json"))
      end
    end
  end
end
