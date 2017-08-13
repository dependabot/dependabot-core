# frozen_string_literal: true
require "dependabot/file_updaters/base"
require "dependabot/file_fetchers/ruby/gemspec"

module Dependabot
  module FileUpdaters
    module Ruby
      class Gemspec < Dependabot::FileUpdaters::Base
        DEPENDENCY_DECLARATION_REGEX =
          /^\s*\w*\.add(?:_development)?_dependency
            (\s*|\()['"](?<name>.*?)['"],
            \s*(?<requirements>['"].*['"])\)?/x

        def updated_dependency_files
          [
            updated_file(
              file: gemspec,
              content: updated_gemspec_content
            )
          ]
        end

        private

        def required_files
          Dependabot::FileFetchers::Ruby::Gemspec.required_files
        end

        def gemspec
          @gemspec ||= dependency_files.find do |file|
            file.name.end_with?(".gemspec")
          end
        end

        def updated_gemspec_content
          @updated_gemspec_content ||= gemspec.content.gsub(
            original_dependency_declaration_string,
            updated_dependency_declaration_string
          )
        end

        def original_dependency_declaration_string
          @original_dependency_declaration_string ||=
            begin
              matches = []
              gemspec.content.scan(DEPENDENCY_DECLARATION_REGEX) do
                matches << Regexp.last_match
              end
              matches.find { |match| match[:name] == dependency.name }.to_s
            end
        end

        def updated_dependency_declaration_string
          original_requirement = DEPENDENCY_DECLARATION_REGEX.match(
            original_dependency_declaration_string
          )[:requirements]

          formatted_new_requirement =
            dependency.version.split(",").map { |r| %("#{r.strip}") }.join(", ")

          original_dependency_declaration_string.
            sub(original_requirement, formatted_new_requirement)
        end
      end
    end
  end
end
