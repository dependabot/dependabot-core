# frozen_string_literal: true
require "bump/dependency_file"
require "bump/dependency"
require "bump/dependency_file_parsers/python"

module Bump
  module DependencyFileUpdaters
    class Python
      attr_reader :requirements, :dependency

      def initialize(dependency_files:, dependency:, github_access_token:)
        @requirements =
          dependency_files.find { |f| f.name == "requirements.txt" }

        raise "No requirements.txt!" unless requirements

        @github_access_token = github_access_token
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

        requirements.content.
          to_enum(:scan,
                  DependencyFileParsers::Python::LineParser::REQUIREMENT_LINE).
          find { Regexp.last_match[:name] == dependency.name }

        original_dep_declaration_string = Regexp.last_match.to_s
        updated_dep_declaration_string =
          original_dep_declaration_string.
          sub(DependencyFileParsers::Python::LineParser::REQUIREMENT) do |old|
            old_version =
              old.match(DependencyFileParsers::Python::LineParser::VERSION)[0]

            precision = old_version.split(".").count
            new_version =
              dependency.version.split(".").first(precision).join(".")

            old.sub(old_version, new_version)
          end

        @updated_requirements_content = requirements.content.gsub(
          original_dep_declaration_string,
          updated_dep_declaration_string
        )
      end
    end
  end
end
