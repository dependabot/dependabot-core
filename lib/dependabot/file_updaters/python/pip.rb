# frozen_string_literal: true
require "python_requirement_line_parser"
require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    module Python
      class Pip < Dependabot::FileUpdaters::Base
        def self.updated_files_regex
          [
            /^requirements\.txt$/,
            /^constraints\.txt$/
          ]
        end

        def updated_dependency_files
          changed_requirements =
            dependency.requirements - dependency.previous_requirements

          changed_requirements.map do |req|
            updated_file(
              file: original_file(req.fetch(:file)),
              content: updated_file_content(req)
            )
          end
        end

        private

        def check_required_files
          %w(requirements.txt).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def original_file(filename)
          file = get_original_file(filename)
          raise "No #{filename} in #{dependency_files.map(&:name)}!" unless file
          file
        end

        def updated_file_content(requirement)
          original_file(requirement.fetch(:file)).content.gsub(
            original_dependency_declaration_string(requirement),
            updated_dependency_declaration_string(requirement)
          )
        end

        def original_dependency_declaration_string(requirements)
          regex = PythonRequirementLineParser::REQUIREMENT_LINE
          matches = []

          original_file(requirements.fetch(:file)).
            content.scan(regex) { matches << Regexp.last_match }
          dec = matches.find { |match| match[:name] == dependency.name }
          raise "Declaration not found!" unless dec
          dec.to_s
        end

        def updated_dependency_declaration_string(requirement)
          original_dependency_declaration_string(requirement).
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
