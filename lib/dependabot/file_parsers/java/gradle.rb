# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"

# The best Gradle documentation is at:
# - https://docs.gradle.org/current/dsl/org.gradle.api.artifacts.dsl.
#   DependencyHandler.html
module Dependabot
  module FileParsers
    module Java
      class Gradle < Dependabot::FileParsers::Base
        require "dependabot/file_parsers/base/dependency_set"

        ATTRS = %w(name group version).freeze
        PROPERTY_REGEX =
          /
            (?:\$\{property\((?<property_name>.*?)\)\})|
            (?:\$\{(?<property_name>.*?)\})|
            (?:\$(?<property_name>.*))
          /x

        DEPENDENCY_DECLARATION_REGEX =
          /(?:\(|\s)\s*['"](?<declaration>[^\s,'":]+:[^\s,'":]+:[^\s,'":]+)['"]/

        PROPERTY_DECLARATION_REGEX =
          /(?:^|\s+|ext.)(?<name>[^\s=]+)\s*=\s*['"](?<value>[^\s]+)['"]/

        def parse
          dependency_set = DependencySet.new
          buildfiles.each do |buildfile|
            dependency_set += buildfile_dependencies(buildfile)
          end
          dependency_set.dependencies
        end

        private

        def map_value_regex(key)
          /(?:^|\s|,|\()#{Regexp.quote(key)}:\s*['"](?<value>[^'"]+)['"]/
        end

        def buildfile_dependencies(buildfile)
          dependency_set = DependencySet.new

          dependency_set += shortform_buildfile_dependencies(buildfile)
          dependency_set += keyword_arg_buildfile_dependencies(buildfile)

          dependency_set
        end

        def shortform_buildfile_dependencies(buildfile)
          dependency_set = DependencySet.new

          buildfile.content.scan(DEPENDENCY_DECLARATION_REGEX) do
            declaration = Regexp.last_match.named_captures.fetch("declaration")
            details = {
              group: declaration.split(":").first,
              name: declaration.split(":")[1],
              version: declaration.split(":").last
            }

            dependency_set <<
              dependency_from(details_hash: details, buildfile: buildfile)
          end

          dependency_set
        end

        def keyword_arg_buildfile_dependencies(buildfile)
          dependency_set = DependencySet.new

          buildfile.content.lines.each do |line|
            name    = line.match(map_value_regex("name"))&.
                      named_captures&.fetch("value")
            group   = line.match(map_value_regex("group"))&.
                      named_captures&.fetch("value")
            version = line.match(map_value_regex("version"))&.
                      named_captures&.fetch("value")
            next unless name && group && version

            details = { name: name, group: group, version: version }

            dependency_set <<
              dependency_from(details_hash: details, buildfile: buildfile)
          end

          dependency_set
        end

        def dependency_from(details_hash:, buildfile:)
          dependency_name = [
            evaluated_value(details_hash[:group], buildfile),
            evaluated_value(details_hash[:name], buildfile)
          ].join(":")

          version_property_name =
            details_hash[:version].
            match(PROPERTY_REGEX)&.
            named_captures&.fetch("property_name")

          Dependency.new(
            name: dependency_name,
            version: evaluated_value(details_hash[:version], buildfile),
            requirements: [{
              requirement:
                evaluated_value(details_hash[:version], buildfile),
              file: buildfile.name,
              source: nil,
              groups: [],
              metadata:
                if version_property_name
                  { property_name: version_property_name }
                end
            }],
            package_manager: "gradle"
          )
        end

        def evaluated_value(value, buildfile)
          return value unless value.match?(PROPERTY_REGEX)

          property_name  = value.match(PROPERTY_REGEX).
                           named_captures.fetch("property_name")
          property_value = properties(buildfile).fetch(property_name, nil)

          return value unless property_value

          value.gsub(PROPERTY_REGEX, property_value)
        end

        def properties(buildfile)
          @properties ||= {}
          return @properties[buildfile.name] if @properties[buildfile.name]

          @properties[buildfile.name] = {}
          buildfile.content.scan(PROPERTY_DECLARATION_REGEX) do
            captures = Regexp.last_match.named_captures
            name = captures.fetch("name").sub(/^ext\./, "")
            @properties[buildfile.name][name] = captures.fetch("value")
          end

          @properties[buildfile.name]
        end

        def buildfiles
          @buildfiles ||=
            dependency_files.select { |f| f.name.end_with?("build.gradle") }
        end

        def check_required_files
          raise "No build.gradle!" unless get_original_file("build.gradle")
        end
      end
    end
  end
end
