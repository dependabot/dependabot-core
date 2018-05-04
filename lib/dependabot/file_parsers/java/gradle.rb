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

            dependency_set << dependency_from(details_hash: dep)
          end

          dependency_set
        end

        def dependency_from(details_hash:)
          dependency_name = [
            evaluated_value(details_hash["group"]),
            evaluated_value(details_hash["name"])
          ].join(":")

          version_property_name =
            details_hash["version"].
            match(PROPERTY_REGEX)&.
            named_captures&.fetch("property_name")

          Dependency.new(
            name: dependency_name,
            version: evaluated_value(details_hash["version"]),
            requirements: [
              {
                requirement: evaluated_value(details_hash["version"]),
                file: buildfile.name,
                source: nil,
                groups: [],
                metadata:
                  if version_property_name
                    { property_name: version_property_name }
                  end
              }
            ],
            package_manager: "gradle"
          )
        end

        def evaluated_value(value)
          return value unless value.match?(PROPERTY_REGEX)

          property_name  = value.match(PROPERTY_REGEX).
                           named_captures.fetch("property_name")
          property_value = properties.fetch(property_name, nil)

          return value unless property_value
          value.gsub(PROPERTY_REGEX, property_value)
        end

        def parsed_buildfile
          @parsed_buildfile ||=
            Dir.chdir(gradle_helper_path) do
              FileUtils.mkdir("target") unless Dir.exist?("target")
              File.write("target/build.gradle", buildfile.content)

              command = "java -jar build/libs/gradle.jar"
              raw_response = nil
              IO.popen(command) do |process|
                raw_response = process.read
              end
              # Raise an error with the output from the shell session if Pipenv
              # returns a non-zero status
              unless $CHILD_STATUS.success?
                raise SharedHelpers::HelperSubprocessFailed.new(
                  raw_response,
                  command
                )
              end

              result = File.read("target/output.json")
              FileUtils.rm_rf("target")
              JSON.parse(result)
            end
        end

        def gradle_helper_path
          File.join(project_root, "helpers/gradle/")
        end

        def project_root
          File.join(File.dirname(__FILE__), "../../../..")
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
