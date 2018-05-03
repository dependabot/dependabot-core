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

        REQUIRED_ATTRS = %w(name group version).freeze

        def parse
          dependency_set = DependencySet.new
          buildfiles.each { |b| dependency_set += buildfile_dependencies(b) }
          dependency_set.dependencies
        end

        private

        def buildfile_dependencies(file)
          dependency_set = DependencySet.new

          parsed_buildfile = parsed_buildfile(file)
          parsed_buildfile["dependencies"].each do |dep|
            next if REQUIRED_ATTRS.any? { |a| dep[a].nil? || dep[a].empty? }
            next if REQUIRED_ATTRS.any? { |a| dep[a].include?("$") }

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

        def parsed_buildfile(file)
          @parsed_buildfile ||=
            Dir.chdir("helpers/gradle/") do
              FileUtils.mkdir("target") unless Dir.exist?("target")
              File.write("target/build.gradle", file.content)

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
