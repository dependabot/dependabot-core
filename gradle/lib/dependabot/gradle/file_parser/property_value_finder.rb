# frozen_string_literal: true

require "dependabot/gradle/file_parser"

module Dependabot
  module Gradle
    class FileParser
      class PropertyValueFinder
        SINGLE_PROPERTY_DECLARATION_REGEX =
          /(?:^|\s+|ext.)(?<name>[^\s=]+)\s*=\s*['"](?<value>[^\s]+)['"]/.
          freeze

        MULTI_PROPERTY_DECLARATION_REGEX =
          /(?:^|\s+|ext.)(?<namespace>[^\s=]+)\s*=\s*\[(?<values>[^\]]+)\]/m.
          freeze

        NAMESPACED_DECLARATION_REGEX =
          /(?:^|\s+)(?<name>[^\s:]+)\s*:\s*['"](?<value>[^\s]+)['"]\s*/.freeze

        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        def property_details(property_name:, callsite_buildfile:)
          # If the root project was specified, just look in the top-level
          # buildfile
          if property_name.start_with?("rootProject.")
            property_name = property_name.sub("rootProject.", "")
            return properties(top_level_buildfile).fetch(property_name, nil)
          end

          # If this project was specified strip the specifier
          if property_name.start_with?("project.")
            property_name = property_name.sub("project.", "")
          end

          # If a `properties` prefix was specified strip that out, too
          if property_name.start_with?("properties.")
            property_name = property_name.sub("properties.", "")
          end

          # Look for a property in the callsite buildfile. If that fails, look
          # for the property in the top-level buildfile
          if properties(callsite_buildfile).fetch(property_name, nil)
            return properties(callsite_buildfile).fetch(property_name)
          end

          properties(top_level_buildfile).fetch(property_name, nil)
        end

        def property_value(property_name:, callsite_buildfile:)
          property_details(
            property_name: property_name,
            callsite_buildfile: callsite_buildfile
          )&.fetch(:value)
        end

        private

        attr_reader :dependency_files

        def properties(buildfile)
          @properties ||= {}
          return @properties[buildfile.name] if @properties[buildfile.name]

          @properties[buildfile.name] = {}

          @properties[buildfile.name].
            merge!(fetch_single_property_declarations(buildfile))

          @properties[buildfile.name].
            merge!(fetch_multi_property_declarations(buildfile))

          @properties[buildfile.name]
        end

        def fetch_single_property_declarations(buildfile)
          properties = {}

          prepared_content(buildfile).scan(SINGLE_PROPERTY_DECLARATION_REGEX) do
            declaration_string = Regexp.last_match.to_s.strip
            captures = Regexp.last_match.named_captures
            name = captures.fetch("name").sub(/^ext\./, "")
            properties[name] = {
              value: captures.fetch("value"),
              declaration_string: declaration_string,
              file: buildfile.name
            }
          end

          properties
        end

        def fetch_multi_property_declarations(buildfile)
          properties = {}

          prepared_content(buildfile).scan(MULTI_PROPERTY_DECLARATION_REGEX) do
            captures = Regexp.last_match.named_captures
            namespace = captures.fetch("namespace").sub(/^ext\./, "")

            captures.fetch("values").scan(NAMESPACED_DECLARATION_REGEX) do
              declaration_string = Regexp.last_match.to_s.strip
              sub_captures = Regexp.last_match.named_captures
              name = sub_captures.fetch("name")
              full_name = [namespace, name].join(".")

              properties[full_name] = {
                value: sub_captures.fetch("value"),
                declaration_string: declaration_string,
                file: buildfile.name
              }
            end
          end

          properties
        end

        def prepared_content(buildfile)
          # Remove any comments
          buildfile.content.
            gsub(%r{(?<=^|\s)//.*$}, "\n").
            gsub(%r{(?<=^|\s)/\*.*?\*/}m, "")
        end

        def top_level_buildfile
          @top_level_buildfile ||=
            dependency_files.find { |f| f.name == "build.gradle" }
        end
      end
    end
  end
end
