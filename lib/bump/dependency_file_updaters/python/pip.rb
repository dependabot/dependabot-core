# frozen_string_literal: true
require "bump/dependency_file_updaters/base"
require "bump/dependency_file_parsers/python/pip"
require "bump/dependency_file_fetchers/python/pip"

module Bump
  module DependencyFileUpdaters
    module Python
      class Pip < Bump::DependencyFileUpdaters::Base
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
          Bump::DependencyFileFetchers::Python::Pip.required_files
        end

        def requirements
          @requirements ||= get_original_file("requirements.txt")
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
              regex =
                DependencyFileParsers::Python::Pip::LineParser::REQUIREMENT_LINE
              matches = []

              requirements.content.scan(regex) { matches << Regexp.last_match }
              matches.find { |match| match[:name] == dependency.name }.to_s
            end
        end

        def updated_dependency_declaration_string
          requirement_regex =
            DependencyFileParsers::Python::Pip::LineParser::REQUIREMENT
          version_regex =
            DependencyFileParsers::Python::Pip::LineParser::VERSION

          original_dependency_declaration_string.
            sub(requirement_regex) do |req|
              req.sub(version_regex) do |ver|
                precision = ver.split(".").count
                dependency.version.split(".").first(precision).join(".")
              end
            end
        end
      end
    end
  end
end
