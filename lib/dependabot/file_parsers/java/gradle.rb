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

        def parse
          dependency_set = DependencySet.new
          buildfiles.each do |buildfile|
            dependency_set += buildfile_dependencies(buildfile)
          end
          dependency_set.dependencies
        end

        private

        def buildfile_dependencies(buildfile)
          dependency_set = DependencySet.new

          parsed_buildfile(buildfile)["dependencies"].each do |dep|
            next if dep.values_at(*ATTRS).any? { |v| v.nil? || v.empty? }

            dependency_set <<
              dependency_from(details_hash: dep, buildfile: buildfile)
          end

          dependency_set
        end

        def dependency_from(details_hash:, buildfile:)
          dependency_name = [
            evaluated_value(details_hash["group"], buildfile),
            evaluated_value(details_hash["name"], buildfile)
          ].join(":")

          version_property_name =
            details_hash["version"].
            match(PROPERTY_REGEX)&.
            named_captures&.fetch("property_name")

          Dependency.new(
            name: dependency_name,
            version: evaluated_value(details_hash["version"], buildfile),
            requirements: [{
              requirement:
                evaluated_value(details_hash["version"], buildfile),
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

        def parsed_buildfile(buildfile)
          @parsed_buildfile ||= {}
          @parsed_buildfile[buildfile.name] ||=
            SharedHelpers.in_a_temporary_directory do
              write_temporary_files(buildfile)

              command = "java -jar #{gradle_parser_path} #{Dir.pwd}"
              raw_response = nil
              IO.popen(command) { |process| raw_response = process.read }

              unless $CHILD_STATUS.success?
                raise SharedHelpers::HelperSubprocessFailed.new(
                  raw_response,
                  command
                )
              end

              result = File.read("result.json")
              JSON.parse(result)
            end
        end

        def write_temporary_files(buildfile)
          File.write(
            "build.gradle",
            prepared_buildfile_content(buildfile.content)
          )
        end

        def gradle_parser_path
          "#{gradle_helper_path}/buildfile_parser.jar"
        end

        def gradle_helper_path
          File.join(project_root, "helpers/gradle/")
        end

        def project_root
          File.join(File.dirname(__FILE__), "../../../..")
        end

        def properties(buildfile)
          @properties ||= {}
          @properties[buildfile.name] ||=
            parsed_buildfile(buildfile)["properties"].
            each_with_object({}) do |prop, hash|
              hash[prop.fetch("name")] = prop.fetch("value")
            end
        end

        def prepared_buildfile_content(buildfile_content)
          buildfile_content.gsub(/^\s*import\s.*$/, "")
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
