# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Maven
    class FileParser
      class MavenDependencyParser
        extend T::Sig
        require "dependabot/file_parsers/base/dependency_set"

        sig do
          params(dependency_files: T::Array[Dependabot::DependencyFile]).returns(Dependabot::FileParsers::Base::DependencySet)
        end
        def parse_dependency_tree(dependency_files)
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new
          dependency_tree = run_mvn_cli_dependency_tree(dependency_files)
          extract_dependencies_from_tree(dependency_set, dependency_tree)
          dependency_set
        end

        sig do
          params(dependency_set: Dependabot::FileParsers::Base::DependencySet,
                 dependency_tree: T::Hash[String, T.untyped]).void
        end
        def extract_dependencies_from_tree(dependency_set, dependency_tree)
          traverse_tree = lambda do |node|
            artifact_id = node["artifactId"]
            group_id = node["groupId"]
            version = node["version"]
            type = node["type"]
            classifier = node["classifier"].to_s.empty? ? nil : node["classifier"]
            scope = node["scope"]

            groups = scope == "test" ? ["test"] : []
            dependency_set << Dependabot::Dependency.new(
              name: "#{group_id}:#{artifact_id}",
              version: version,
              package_manager: "maven",
              requirements: [{
                requirement: version,
                file: "pom.xml", # TODO: nil for transitive dependencies
                groups: groups,
                source: nil,
                metadata: {
                  packaging_type: type,
                  classifier: classifier
                }
              }]
            )

            node["children"]&.each { |child| traverse_tree.call(child) }
          end

          traverse_tree.call(dependency_tree)
        end

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).returns(T::Hash[String, T.untyped]) }
        def run_mvn_cli_dependency_tree(dependency_files)
          # Copy only pom.xml files to a temporary directory to
          # output the dependency tree without building the project
          SharedHelpers.in_a_temporary_directory do |path|
            dependency_files.each do |pom|
              File.write(File.join(path, pom.name), pom.content)
            end

            _, stderr, status = Open3.capture3("mvn dependency:tree -DoutputFile=output.json -DoutputType=json -e")
            raise "Failed to execute mvn dependency:tree: #{stderr}" unless status.success?

            output_file = File.join(path, "output.json")
            raise "Output file not found!" unless File.exist?(output_file)

            JSON.parse(File.read(output_file))
          end
        end
      end
    end
  end
end
