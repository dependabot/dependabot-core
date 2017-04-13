# frozen_string_literal: true
require "bump/dependency_file"
require "bump/dependency"
require "bump/dependency_file_parsers/python"

module Bump
  module DependencyFileUpdaters
    class Python
      attr_reader :requirements, :dependency

      def initialize(dependency_files:, dependency:)
        @packages = DependencyFileParsers::Python.new(
          dependency_files: dependency_files
        ).parse

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

      def updated_requirements_content
        return @updated_requirements_content if @updated_requirements_content

        packages = @packages.map do |pkg|
          next pkg unless pkg.name == dependency.name
          next pkg unless pkg.version
          old_version = pkg.version

          Dependency.new(
            name: pkg.name,
            version: updated_version_string(old_version, dependency.version)
          )
        end

        @updated_requirements_content = packages.map do |pkg|
          "#{pkg.name}==#{pkg.version}"
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
end
