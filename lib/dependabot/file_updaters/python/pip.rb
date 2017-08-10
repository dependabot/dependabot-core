# frozen_string_literal: true
require "dependabot/file_updaters/base"
require "dependabot/file_fetchers/python/pip"

module Dependabot
  module FileUpdaters
    module Python
      class Pip < Dependabot::FileUpdaters::Base
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
              regex = LineParser::REQUIREMENT_LINE
              matches = []

              requirements.content.scan(regex) { matches << Regexp.last_match }
              matches.find { |match| match[:name] == dependency.name }.to_s
            end
        end

        def updated_dependency_declaration_string
          original_dependency_declaration_string.
            sub(LineParser::REQUIREMENT) do |req|
              req.sub(LineParser::VERSION) do |ver|
                precision = ver.split(".").count
                dependency.version.segments.first(precision).join(".")
              end
            end
        end

        class LineParser
          NAME = /[a-zA-Z0-9\-_\.]+/
          EXTRA = /[a-zA-Z0-9\-_\.]+/
          COMPARISON = /===|==|>=|<=|<|>|~=|!=/
          VERSION = /[a-zA-Z0-9\-_\.]+/
          REQUIREMENT = /(?<comparison>#{COMPARISON})\s*(?<version>#{VERSION})/

          REQUIREMENT_LINE =
            /^\s*(?<name>#{NAME})
              \s*(\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
              \s*(?<requirements>#{REQUIREMENT}(\s*,\s*#{REQUIREMENT})*)?
              \s*#*\s*(?<comment>.+)?$
            /x

          def self.parse(line)
            requirement = line.chomp.match(REQUIREMENT_LINE)
            return if requirement.nil?

            requirements =
              requirement[:requirements].to_s.
              to_enum(:scan, REQUIREMENT).
              map do
                {
                  comparison: Regexp.last_match[:comparison],
                  version: Regexp.last_match[:version]
                }
              end

            {
              name: requirement[:name],
              requirements: requirements
            }
          end
        end
      end
    end
  end
end
