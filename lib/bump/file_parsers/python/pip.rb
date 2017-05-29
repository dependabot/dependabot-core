# frozen_string_literal: true
require "bump/dependency"
require "bump/file_parsers/base"
require "bump/file_fetchers/python/pip"

module Bump
  module FileParsers
    module Python
      class Pip < Bump::FileParsers::Base
        def parse
          requirements.
            content.
            each_line.
            each_with_object([]) do |line, dependencies|
              dependency = LineParser.parse(line)

              next if dependency.nil?
              next if dependency[:requirements].length.zero?

              # Ignore dependencies with multiple requirements, since they would
              # cause trouble at the dependency update step
              next if dependency[:requirements].length > 1

              dependencies << Dependency.new(
                name: dependency[:name],
                version: dependency[:requirements].first[:version],
                package_manager: "pip"
              )
            end
        end

        private

        def required_files
          Bump::FileFetchers::Python::Pip.required_files
        end

        def requirements
          @requirements ||= get_original_file("requirements.txt")
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
