# frozen_string_literal: true

require "dependabot/sbt/file_parser"

module Dependabot
  module Sbt
    class FileParser
      class ScalaVersionsFinder
        SCALA_VERSION_DECLARATION_REGEX =
          /^.*scalaVersion.*:=.*"(?<scala_version>\d\.\d{2}).*?".*$/.freeze

        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        def cross_build_versions
          scala_versions = []

          @dependency_files.
            select { |dep| File.extname(dep.name) == ".sbt" }.
            map(&:content).
            each do |content|
              content.scan(SCALA_VERSION_DECLARATION_REGEX) do
                named_captures = Regexp.last_match.named_captures
                next unless named_captures.fetch("scala_version")

                scala_versions << named_captures.fetch("scala_version")
              end
            end

          scala_versions
        end
      end
    end
  end
end
