# frozen_string_literal: true
require "bump/dependency"

module Bump
  module DependencyFileParsers
    class Python
      def initialize(dependency_files:)
        @requirements = dependency_files.find do |f|
          f.name == "requirements.txt"
        end

        raise "No requirements.txt!" unless @requirements
      end

      def parse
        @requirements.
          content.
          each_line.
          each_with_object([]) do |line, dependencies|
            dependency = LineParser.new(line).parse

            next if dependency.nil?
            next if dependency[:requirements].length.zero?

            # Ignore dependencies with multiple requirements, since they would
            # cause trouble at the dependency update step
            next if dependency[:requirements].length > 1

            version =
              dependency[:requirements].first.match(LineParser::VERSION)[0]

            dependencies << Dependency.new(
              name: dependency[:name],
              version: version,
              language: "python"
            )
          end
      end

      class LineParser
        NAME = /[a-zA-Z0-9\-_\.]+/
        EXTRA = /[a-zA-Z0-9\-_\.]+/
        COMPARISON = /===|==|>=|<=|<|>|~=|!=/
        VERSION = /[a-zA-Z0-9\-_\.]+/
        REQUIREMENT = /#{COMPARISON}\s*#{VERSION}/

        REQUIREMENT_LINE =
          /^\s*(?<name>#{NAME})
            \s*(\[\s*(?<extras>#{EXTRA}(\s*,\s*#{EXTRA})*)\s*\])?
            \s*(?<requirements>#{REQUIREMENT}(\s*,\s*#{REQUIREMENT})*)?
            \s*#*\s*(?<comment>.+)?$
          /x

        attr_reader :line

        def initialize(line)
          @line = line
        end

        def parse
          requirement = line.chomp.match(REQUIREMENT_LINE)
          return if requirement.nil?

          {
            name: requirement[:name],
            requirements: (requirement[:requirements] || "").scan(REQUIREMENT)
          }
        end
      end
    end
  end
end
