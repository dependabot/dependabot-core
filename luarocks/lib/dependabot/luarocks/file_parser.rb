# frozen_string_literal: true

require "open3"
require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/errors"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"

module Dependabot
  module LuaRocks
    class FileParser < Dependabot::FileParsers::Base
      DEPENDENCY_REGEX = /^"(?<name>\w+)\s(?<operator>[~<>=]{0,2})\s?(?<version>[\w\.]+)",?$/

      def parse
        dependency_set = DependencySet.new

        dependency_files.each do |rockspec|
          rockspec.content.each_line do |line|
            line_strip = line.strip()

            next unless DEPENDENCY_REGEX.match?(line_strip)

            parsed_from_line = DEPENDENCY_REGEX.match(line_strip).named_captures

            operator = parsed_from_line.fetch("operator") || "="
            version = parsed_from_line.fetch("version")

            dependency_set << Dependency.new(
              name: parsed_from_line.fetch("name"),
              version: version,
              package_manager: "luarocks",
              requirements: [
                requirement: LuaRocks::Requirement.new("#{operator} #{version}"),
                groups: [],
                file: rockspec.name,
                source: nil
              ]
            )
          end
        end

        dependency_set.dependencies
      end

      private

      def check_required_files
        # Just check if there are any files at all.
        return if dependency_files.any?

        raise "No Rockspec!"
      end

    end
  end
end

Dependabot::FileParsers.
  register("luarocks", Dependabot::LuaRocks::FileParser)
