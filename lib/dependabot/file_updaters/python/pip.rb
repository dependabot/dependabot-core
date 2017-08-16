# frozen_string_literal: true
require "python_requirement_line_parser"
require "dependabot/file_updaters/base"
require "dependabot/file_fetchers/python/pip"

module Dependabot
  module FileUpdaters
    module Python
      class Pip < Dependabot::FileUpdaters::Base
        def self.updated_files_regex
          [/^requirements\.txt$/]
        end

        def updated_dependency_files
          [
            updated_file(
              file: requirements,
              content: updated_requirements_content
            )
          ]
        end

        private

        def required_files
          Dependabot::FileFetchers::Python::Pip.required_files
        end

        def requirements
          @requirements ||= dependency_files.find do |file|
            next if file.name.end_with?("setup.py")
            file.content.match?(/^#{Regexp.escape(dependency.name)}==/)
          end
        end

        def updated_requirements_content
          @updated_requirements_content ||= requirements.content.gsub(
            original_dependency_declaration_string,
            updated_dependency_declaration_string
          )
        end

        def original_dependency_declaration_string
          @original_dependency_declaration_string ||=
            begin
              regex = PythonRequirementLineParser::REQUIREMENT_LINE
              matches = []

              requirements.content.scan(regex) { matches << Regexp.last_match }
              matches.find { |match| match[:name] == dependency.name }.to_s
            end
        end

        def updated_dependency_declaration_string
          original_dependency_declaration_string.
            sub(PythonRequirementLineParser::REQUIREMENT) do |req|
              req.sub(PythonRequirementLineParser::VERSION) do |ver|
                precision = ver.split(".").count
                dependency.version.split(".").first(precision).join(".")
              end
            end
        end
      end
    end
  end
end
