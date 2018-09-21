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
        require_relative "gradle/property_value_finder"

        ATTRS = %w(name group version).freeze
        PROPERTY_REGEX =
          /
            (?:\$\{property\((?<property_name>[^:\s]*?)\)\})|
            (?:\$\{(?<property_name>[^:\s]*?)\})|
            (?:\$(?<property_name>[^:\s]*))
          /x

        PART = %r{[^\s,@'":/\\]+}
        VSN_PART = %r{[^\s,'":/\\]+}
        DEPENDENCY_DECLARATION_REGEX =
          /(?:\(|\s)\s*['"](?<declaration>#{PART}:#{PART}:#{VSN_PART})['"]/

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

          prepared_content(buildfile).scan(DEPENDENCY_DECLARATION_REGEX) do
            declaration = Regexp.last_match.named_captures.fetch("declaration")
            details = {
              group: declaration.split(":").first,
              name: declaration.split(":")[1],
              version: declaration.split(":").last
            }

            dep = dependency_from(details_hash: details, buildfile: buildfile)
            dependency_set << dep if dep
          end

          dependency_set
        end

        def keyword_arg_buildfile_dependencies(buildfile)
          dependency_set = DependencySet.new

          prepared_content(buildfile).lines.each do |line|
            name    = line.match(map_value_regex("name"))&.
                      named_captures&.fetch("value")
            group   = line.match(map_value_regex("group"))&.
                      named_captures&.fetch("value")
            version = line.match(map_value_regex("version"))&.
                      named_captures&.fetch("value")
            next unless name && group && version

            details = { name: name, group: group, version: version }

            dep = dependency_from(details_hash: details, buildfile: buildfile)
            dependency_set << dep if dep
          end

          dependency_set
        end

        def dependency_from(details_hash:, buildfile:)
          group   = evaluated_value(details_hash[:group], buildfile)
          name    = evaluated_value(details_hash[:name], buildfile)
          version = evaluated_value(details_hash[:version], buildfile)

          dependency_name = "#{group}:#{name}"

          # If we couldn't evaluate a property they we won't be able to
          # update this dependency
          return if "#{dependency_name}:#{version}".match?(PROPERTY_REGEX)

          version_property_name =
            details_hash[:version].
            match(PROPERTY_REGEX)&.
            named_captures&.fetch("property_name")

          Dependency.new(
            name: dependency_name,
            version: version,
            requirements: [{
              requirement: version,
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
          property_value = property_value_finder.property_value(
            property_name: property_name,
            callsite_buildfile: buildfile
          )

          return value unless property_value

          value.gsub(PROPERTY_REGEX, property_value)
        end

        def property_value_finder
          @property_value_finder ||=
            PropertyValueFinder.new(dependency_files: dependency_files)
        end

        def prepared_content(buildfile)
          # Remove any comments
          prepared_content =
            buildfile.content.
            gsub(%r{(?<=^|\s)//.*$}, "\n").
            gsub(%r{(?<=^|\s)/\*.*?\*/}m, "")

          # Remove the dependencyVerification section added by Gradle Witness
          # (TODO: Support updating this in the FileUpdater)
          prepared_content.dup.scan(/dependencyVerification\s*{/) do
            mtch = Regexp.last_match
            block = mtch.post_match[0..closing_bracket_index(mtch.post_match)]
            prepared_content.gsub!(block, "")
          end

          prepared_content
        end

        def closing_bracket_index(string)
          closes_required = 1

          string.chars.each_with_index do |char, index|
            closes_required += 1 if char == "{"
            closes_required -= 1 if char == "}"
            return index if closes_required.zero?
          end
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
