# frozen_string_literal: true

require "python_requirement_parser"
require "dependabot/file_updaters/base"

module Dependabot
  module FileUpdaters
    module Python
      class Pip < Dependabot::FileUpdaters::Base
        def self.updated_files_regex
          [
            /^requirements\.txt$/,
            /^constraints\.txt$/,
            /^setup\.py$/
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

        def dependency
          # For now, we'll only ever be updating a single dependency for Python
          dependencies.first
        end

        def check_required_files
          return if get_original_file("requirements.txt")
          return if get_original_file("setup.py")
          raise "No requirements.txt or setup.py!"
        end

        def original_file(filename)
          get_original_file(filename)
        end

        def updated_file_content(requirement)
          original_file(requirement.fetch(:file)).content.gsub(
            original_dependency_declaration_string(requirement),
            updated_dependency_declaration_string(requirement)
          )
        end

        def original_dependency_declaration_string(requirements)
          regex = PythonRequirementParser::INSTALL_REQ_WITH_REQUIREMENT
          matches = []

          original_file(requirements.fetch(:file)).
            content.scan(regex) { matches << Regexp.last_match }
          dec = matches.find { |match| match[:name] == dependency.name }
          raise "Declaration not found for #{dependency.name}!" unless dec
          dec.to_s
        end

        def updated_dependency_declaration_string(requirement)
          original_dependency_declaration_string(requirement).sub(
            PythonRequirementParser::REQUIREMENTS,
            requirement.fetch(:requirement)
          )
        end
      end
    end
  end
end
