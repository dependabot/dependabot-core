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
          dependency_set += buildfile_dependencies
          dependency_set.dependencies
        end

        private

        def buildfile_dependencies
          dependency_set = DependencySet.new

          parsed_buildfile["dependencies"].each do |dep|
            next if dep.values_at(*ATTRS).any? { |v| v.nil? || v.empty? }
            dep = interpolate_property_values(dep)
            next if dep.values_at(*ATTRS).any? { |v| v.include?("$") }

            dependency_set <<
              Dependency.new(
                name: "#{dep['group']}:#{dep['name']}",
                version: dep["version"],
                requirements: [
                  {
                    requirement: dep["version"],
                    file: buildfile.name,
                    source: nil,
                    groups: []
                    # TODO: Include details of property here
                  }
                ],
                package_manager: "gradle"
              )
          end

          dependency_set
        end

        def interpolate_property_values(details)
          details = details.dup
          details.each do |key, value|
            next unless value.match?(PROPERTY_REGEX)
            details[key] =
              value.gsub(PROPERTY_REGEX) do |match_string|
                property = match_string.
                           match(PROPERTY_REGEX).
                           named_captures["property_name"]
                properties[property] || match_string
              end
          end

          details
        end

        def parsed_buildfile
          @parsed_buildfile ||=
            Dir.chdir("helpers/gradle/") do
              FileUtils.mkdir("target") unless Dir.exist?("target")
              File.write("target/build.gradle", buildfile.content)

              raw_response = nil
              IO.popen("java -jar build/libs/gradle.jar") do |process|
                raw_response = process.read
              end
              raise unless $CHILD_STATUS.success?

              result = File.read("target/output.json")
              FileUtils.rm_rf("target")
              JSON.parse(result)
            end
        end

        def properties
          @properties ||=
            parsed_buildfile["properties"].each_with_object({}) do |prop, hash|
              hash[prop.fetch("name")] = prop.fetch("value")
            end
        end

        def buildfile
          @buildfile ||=
            dependency_files.find { |f| f.name == "build.gradle" }
        end

        def check_required_files
          raise "No build.gradle!" unless get_original_file("build.gradle")
        end
      end
    end
  end
end
