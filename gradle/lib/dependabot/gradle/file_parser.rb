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

        PROPERTY_REGEX =
          /
            (?:\$\{property\((?<property_name>[^:\s]*?)\)\})|
            (?:\$\{(?<property_name>[^:\s]*?)\})|
            (?:\$(?<property_name>[^:\s]*))
          /x.freeze

        PART = %r{[^\s,@'":/\\]+}.freeze
        VSN_PART = %r{[^\s,'":/\\]+}.freeze
        DEPENDENCY_DECLARATION_REGEX =
          /(?:\(|\s)\s*['"](?<declaration>#{PART}:#{PART}:#{VSN_PART})['"]/.
          freeze
        DEPENDENCY_SET_DECLARATION_REGEX =
          /(?:^|\s)dependencySet\((?<arguments>[^\)]+)\)\s*\{/.freeze
        DEPENDENCY_SET_ENTRY_REGEX = /entry\s+['"](?<name>#{PART})['"]/.freeze

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
          dependency_set += dependency_set_dependencies(buildfile)

          dependency_set
        end

        def shortform_buildfile_dependencies(buildfile)
          dependency_set = DependencySet.new

          prepared_content(buildfile).scan(DEPENDENCY_DECLARATION_REGEX) do
            declaration = Regexp.last_match.named_captures.fetch("declaration")

            group, name, version = declaration.split(":")
            details = { group: group, name: name, version: version }

            dep = dependency_from(details_hash: details, buildfile: buildfile)
            dependency_set << dep if dep
          end

          dependency_set
        end

        def keyword_arg_buildfile_dependencies(buildfile)
          dependency_set = DependencySet.new

          prepared_content(buildfile).lines.each do |line|
            name    = argument_from_string(line, "name")
            group   = argument_from_string(line, "group")
            version = argument_from_string(line, "version")
            next unless name && group && version

            details = { name: name, group: group, version: version }

            dep = dependency_from(details_hash: details, buildfile: buildfile)
            dependency_set << dep if dep
          end

          dependency_set
        end

        def dependency_set_dependencies(buildfile)
          dependency_set = DependencySet.new

          dependency_set_blocks = []

          prepared_content(buildfile).scan(DEPENDENCY_SET_DECLARATION_REGEX) do
            mch = Regexp.last_match
            dependency_set_blocks <<
              {
                arguments: mch.named_captures.fetch("arguments"),
                block: mch.post_match[0..closing_bracket_index(mch.post_match)]
              }
          end

          dependency_set_blocks.each do |blk|
            group   = argument_from_string(blk[:arguments], "group")
            version = argument_from_string(blk[:arguments], "version")

            next unless group && version

            blk[:block].scan(DEPENDENCY_SET_ENTRY_REGEX).flatten.each do |name|
              dep = dependency_from(
                details_hash: { group: group, name: name, version: version },
                buildfile: buildfile,
                in_dependency_set: true
              )
              dependency_set << dep if dep
            end
          end

          dependency_set
        end

        def argument_from_string(string, arg_name)
          string.
            match(map_value_regex(arg_name))&.
            named_captures&.
            fetch("value")
        end

        def dependency_from(details_hash:, buildfile:, in_dependency_set: false)
          group   = evaluated_value(details_hash[:group], buildfile)
          name    = evaluated_value(details_hash[:name], buildfile)
          version = evaluated_value(details_hash[:version], buildfile)

          dependency_name = "#{group}:#{name}"

          # If we can't evaluate a property they we won't be able to
          # update this dependency
          return if "#{dependency_name}:#{version}".match?(PROPERTY_REGEX)

          Dependency.new(
            name: dependency_name,
            version: version,
            requirements: [{
              requirement: version,
              file: buildfile.name,
              source: nil,
              groups: [],
              metadata: dependency_metadata(details_hash, in_dependency_set)
            }],
            package_manager: "gradle"
          )
        end

        def dependency_metadata(details_hash, in_dependency_set)
          version_property_name =
            details_hash[:version].
            match(PROPERTY_REGEX)&.
            named_captures&.fetch("property_name")

          return unless version_property_name || in_dependency_set

          metadata = {}
          if version_property_name
            metadata[:property_name] = version_property_name
          end
          if in_dependency_set
            metadata[:dependency_set] = {
              group: details_hash[:group],
              version: details_hash[:version]
            }
          end
          metadata
        end

        def evaluated_value(value, buildfile)
          return value unless value.scan(PROPERTY_REGEX).count == 1

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
