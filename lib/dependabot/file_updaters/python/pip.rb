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
          [
            updated_file(
              file: original_file,
              content: updated_requirements_content
            )
          ]
        end

        private

        def check_required_files
          %w(requirements.txt).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end

        def original_file
          filename = dependency.requirements.first.fetch(:file)

          @original_file ||=
            begin
              file = get_original_file(filename)
              unless file
                raise "No #{filename} in #{dependency_files.map(&:name)}!"
              end
              file
            end
        end

        def updated_requirements_content
          @updated_requirements_content ||= original_file.content.gsub(
            original_dependency_declaration_string,
            updated_dependency_declaration_string
          )
        end

        def original_dependency_declaration_string
          @original_dependency_declaration_string ||=
            begin
              regex = PythonRequirementLineParser::REQUIREMENT_LINE
              matches = []

              original_file.content.scan(regex) { matches << Regexp.last_match }
              dec = matches.find { |match| match[:name] == dependency.name }
              raise "Declaration not found!" unless dec
              dec.to_s
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
