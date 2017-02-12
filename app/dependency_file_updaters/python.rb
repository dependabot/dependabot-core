require "./app/dependency_file"
require "bundler"
require "./lib/shared_helpers"
require "./lib/python_helpers"

module DependencyFileUpdaters
  class Python
    attr_reader :requirements, :dependency

    def initialize(dependency_files:, dependency:)
      @requirements = dependency_files.find { |f| f.name == "requirements.txt" }
      validate_files_are_present!

      @dependency = dependency
    end

    def updated_dependency_files
      [updated_requirements_file]
    end

    def updated_requirements_file
      DependencyFile.new(
        name: "requirements.txt",
        content: updated_requirements_content
      )
    end

    private

    def validate_files_are_present!
      raise "No requirements.txt!" unless requirements
    end

    def updated_requirements_content
      return @updated_requirements_content if @updated_requirements_content

      packages = PythonHelpers.requirements_parse(@requirements.content)

      packages.each do |pkg|
        next unless pkg[0] == dependency.name
        old_version_string = pkg[1]
        next unless old_version_string

        pkg[1] = updated_version_string(old_version_string, dependency.version)
      end

      @updated_requirements_content = packages.map do |pkg|
        "#{pkg[0]}==#{pkg[1]}"
      end.join("\n") + "\n"
    end

    def updated_version_string(old_version_string, new_version_number)
      old_version_string.sub(/[\d\.]*\d/) do |old_version_number|
        precision = old_version_number.split(".").count
        new_version_number.split(".").first(precision).join(".")
      end
    end
  end
end
