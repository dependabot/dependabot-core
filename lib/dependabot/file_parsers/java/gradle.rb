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

        def parse
          dependency_set = DependencySet.new
          buildfiles.each { |b| dependency_set += buildfile_dependencies(b) }
          dependency_set.dependencies
        end

        private

        def buildfile_dependencies(file)
          dependency_set = DependencySet.new

          parsed_buildfile["dependencies"].each do |dep|
            next unless dep["name"] && !dep["name"].empty?
            next unless dep["group"] && !dep["group"].empty?
            next unless dep["version"] && !dep["version"].empty?

            dependency_set <<
              Dependency.new(
                name: "#{dep['group']}:#{dep['name']}",
                version: dep["version"],
                requirements: [
                  {
                    requirement: dep["version"],
                    file: file.name,
                    source: nil,
                    groups: []
                  }
                ],
                package_manager: "gradle"
              )
          end

          dependency_set
        end

        def parsed_buildfile
          @parsed_buildfile ||=
            SharedHelpers.in_a_temporary_directory do
              buildfiles.each do |file|
                path = file.name
                FileUtils.mkdir_p(Pathname.new(path).dirname)
                File.write(file.name, file.content)
              end

              project_root = File.join(File.dirname(__FILE__), "../../../..")
              helper_path = File.join(project_root, "helpers/gradle/bin/run.js")

              parsed_file = SharedHelpers.run_helper_subprocess(
                command: "node #{helper_path}",
                function: "parse",
                args: [Dir.pwd]
              )

              JSON.parse(parsed_file)
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
