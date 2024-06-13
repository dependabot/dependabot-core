# typed: true
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"

module DummyPackageManager
  class FileParser < Dependabot::FileParsers::Base
    require "dependabot/file_parsers/base/dependency_set"

    def parse
      dependency_set = DependencySet.new

      dependency_files.each do |dependency_file|
        dependency_file.content.each_line do |line|
          name, version = line.strip.split(" = ")

          dependency_set << Dependabot::Dependency.new(
            name: name,
            version: version,
            package_manager: "dummy",
            requirements: [
              requirement: version.to_s,
              groups: [],
              file: dependency_file.name,
              source: nil
            ],
            directory: source&.directory,
          )
        end
      end

      dependency_set.dependencies
    end

    private

    def check_required_files
      # Just check if there are any files at all.
      return if dependency_files.any?

      raise "No dependency files!"
    end
  end
end

Dependabot::FileParsers.register("dummy", DummyPackageManager::FileParser)
