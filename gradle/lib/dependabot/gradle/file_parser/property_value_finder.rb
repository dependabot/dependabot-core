# typed: true
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/gradle/file_parser"

module Dependabot
  module Gradle
    class FileParser
      class PropertyValueFinder
        extend T::Sig

        # rubocop:disable Layout/LineLength
        SUPPORTED_BUILD_FILE_NAMES = %w(build.gradle build.gradle.kts).freeze

        QUOTED_VALUE_REGEX = /\s*['"][^\s]+['"]\s*/

        # project.findProperty('property') ?:
        FIND_PROPERTY_REGEX = /\s*project\.findProperty\(#{QUOTED_VALUE_REGEX}\)\s*\?:/

        # project.hasProperty('property') ? project.getProperty('property') :
        GROOVY_HAS_PROPERTY_REGEX =
          /\s*project\.hasProperty\(#{QUOTED_VALUE_REGEX}\)\s*\?\s*project\.getProperty\(#{QUOTED_VALUE_REGEX}\)\s*:/

        # if(project.hasProperty("property")) project.getProperty("property") else
        KOTLIN_HAS_PROPERTY_REGEX =
          /\s*if\s*\(project\.hasProperty\(#{QUOTED_VALUE_REGEX}\)\)\s+project\.getProperty\(#{QUOTED_VALUE_REGEX}\)\s+else\s+/

        GROOVY_PROPERTY_DECLARATION_AS_DEFAULTS_REGEX = /(?:#{FIND_PROPERTY_REGEX}|#{GROOVY_HAS_PROPERTY_REGEX})?/

        KOTLIN_PROPERTY_DECLARATION_AS_DEFAULTS_REGEX = /(?:#{FIND_PROPERTY_REGEX}|#{KOTLIN_HAS_PROPERTY_REGEX})?/

        PROPERTY_DECLARATION_AS_DEFAULTS_REGEX =
          /(#{GROOVY_PROPERTY_DECLARATION_AS_DEFAULTS_REGEX}|#{KOTLIN_PROPERTY_DECLARATION_AS_DEFAULTS_REGEX})?/

        VALUE_REGEX = /#{PROPERTY_DECLARATION_AS_DEFAULTS_REGEX}\s*['"](?<value>[^\s]+)['"]/

        GROOVY_SINGLE_PROPERTY_DECLARATION_REGEX = /(?:^|\s+|ext.)(?<name>[^\s=]+)\s*=#{VALUE_REGEX}/

        KOTLIN_SINGLE_PROPERTY_INDEX_DECLARATION_REGEX = /\s*extra\[['"](?<name>[^\s=]+)['"]\]\s*=#{VALUE_REGEX}/

        KOTLIN_SINGLE_PROPERTY_SET_REGEX = /\s*set\(['"](?<name>[^\s=]+)['"]\s*,#{VALUE_REGEX}\)/

        KOTLIN_SINGLE_PROPERTY_SET_DECLARATION_REGEX = /\s*extra\.#{KOTLIN_SINGLE_PROPERTY_SET_REGEX}/

        KOTLIN_SINGLE_PROPERTY_DECLARATION_REGEX =
          /(#{KOTLIN_SINGLE_PROPERTY_INDEX_DECLARATION_REGEX}|#{KOTLIN_SINGLE_PROPERTY_SET_DECLARATION_REGEX})/

        SINGLE_PROPERTY_DECLARATION_REGEX =
          /(#{KOTLIN_SINGLE_PROPERTY_DECLARATION_REGEX}|#{GROOVY_SINGLE_PROPERTY_DECLARATION_REGEX})/

        GROOVY_MULTI_PROPERTY_DECLARATION_REGEX = /(?:^|\s+|ext.)(?<namespace>[^\s=]+)\s*=\s*\[(?<values>[^\]]+)\]/m

        KOTLIN_BLOCK_PROPERTY_DECLARATION_REGEX = /\s*(?<namespace>[^\s=]+)\.apply\s*{(?<values>[^\]]+)}/m

        KOTLIN_MULTI_PROPERTY_DECLARATION_REGEX =
          /\s*extra\[['"](?<namespace>[^\s=]+)['"]\]\s*=\s*mapOf\((?<values>[^\]]+)\)/m

        MULTI_PROPERTY_DECLARATION_REGEX =
          /(#{KOTLIN_MULTI_PROPERTY_DECLARATION_REGEX}|#{GROOVY_MULTI_PROPERTY_DECLARATION_REGEX})/

        KOTLIN_MAP_NAMESPACED_DECLARATION_REGEX = /(?:^|\s+)['"](?<name>[^\s:]+)['"]\s*to#{VALUE_REGEX}\s*/

        REGULAR_NAMESPACED_DECLARATION_REGEX = /(?:^|\s+)(?<name>[^\s:]+)\s*[:=]#{VALUE_REGEX}\s*/

        NAMESPACED_DECLARATION_REGEX =
          /(#{REGULAR_NAMESPACED_DECLARATION_REGEX}|#{KOTLIN_MAP_NAMESPACED_DECLARATION_REGEX})/
        # rubocop:enable Layout/LineLength

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
          property_name = property_name.sub("project.", "") if property_name.start_with?("project.")

          # If a `properties` prefix was specified strip that out, too
          property_name = property_name.sub("properties.", "") if property_name.start_with?("properties.")

          # Look for a property in the callsite buildfile. If that fails, look
          # for the property in the top-level buildfile
          all_files = [callsite_buildfile, top_level_buildfile].concat(
            FileParser.find_includes(callsite_buildfile, dependency_files),
            FileParser.find_includes(top_level_buildfile, dependency_files)
          ).compact
          all_files.each do |file|
            details = properties(file).fetch(property_name, nil)
            return details if details
          end
          nil
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

          @properties[buildfile.name]
            .merge!(fetch_single_property_declarations(buildfile))

          @properties[buildfile.name]
            .merge!(fetch_kotlin_block_property_declarations(buildfile))

          @properties[buildfile.name]
            .merge!(fetch_multi_property_declarations(buildfile))

          @properties[buildfile.name]
        end

        def fetch_single_property_declarations(buildfile)
          properties = {}

          prepared_content(buildfile).scan(SINGLE_PROPERTY_DECLARATION_REGEX) do
            declaration_string = Regexp.last_match.to_s.strip
            captures = T.must(Regexp.last_match).named_captures
            name = T.must(captures.fetch("name")).sub(/^ext\./, "")

            unless properties.key?(name)
              properties[name] = {
                value: captures.fetch("value"),
                declaration_string: declaration_string,
                file: buildfile.name
              }
            end
          end

          properties
        end

        def fetch_kotlin_block_property_declarations(buildfile)
          properties = {}

          prepared_content(buildfile)
            .scan(KOTLIN_BLOCK_PROPERTY_DECLARATION_REGEX) do
              captures = T.must(Regexp.last_match).named_captures
              namespace = captures.fetch("namespace")

              T.must(captures.fetch("values"))
               .scan(KOTLIN_SINGLE_PROPERTY_SET_REGEX) do
                declaration_string = Regexp.last_match.to_s.strip
                sub_captures = T.must(Regexp.last_match).named_captures
                name = sub_captures.fetch("name")
                full_name = if namespace == "extra"
                              name
                            else
                              [namespace, name].join(".")
                            end

                properties[full_name] = {
                  value: sub_captures.fetch("value"),
                  declaration_string: declaration_string,
                  file: buildfile.name
                }
              end
            end

          properties
        end

        def fetch_multi_property_declarations(buildfile)
          properties = {}

          prepared_content(buildfile).scan(MULTI_PROPERTY_DECLARATION_REGEX) do
            captures = T.must(Regexp.last_match).named_captures
            namespace = T.must(captures.fetch("namespace")).sub(/^ext\./, "")

            T.must(captures.fetch("values")).scan(NAMESPACED_DECLARATION_REGEX) do
              declaration_string = Regexp.last_match.to_s.strip
              sub_captures = T.must(Regexp.last_match).named_captures
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
          buildfile.content
                   .gsub(%r{(?<=^|\s)//.*$}, "\n")
                   .gsub(%r{(?<=^|\s)/\*.*?\*/}m, "")
        end

        def top_level_buildfile
          @top_level_buildfile ||= dependency_files.find do |f|
            SUPPORTED_BUILD_FILE_NAMES.include?(f.name)
          end
        end
      end
    end
  end
end
