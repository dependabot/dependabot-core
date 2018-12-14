# frozen_string_literal: true

require "dependabot/gradle/file_parser"

module Dependabot
  module Gradle
    class FileParser
      class PropertyValueFinder
        PROPERTY_DECLARATION_REGEX =
          /(?:^|\s+|ext.)(?<name>[^\s=]+)\s*=\s*['"](?<value>[^\s]+)['"]/.
          freeze

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
          prepared_content(buildfile).scan(PROPERTY_DECLARATION_REGEX) do
            declaration_string = Regexp.last_match.to_s.strip
            captures = Regexp.last_match.named_captures
            name = captures.fetch("name").sub(/^ext\./, "")
            @properties[buildfile.name][name] = {
              value: captures.fetch("value"),
              declaration_string: declaration_string,
              file: buildfile.name
            }
          end

          @properties[buildfile.name]
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
