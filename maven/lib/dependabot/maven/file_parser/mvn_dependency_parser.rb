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
        def build_dependency_set(dependency_files)
          run_mvn_cli_dependency_tree(dependency_files)
        end

        sig do
          params(pom: Dependabot::DependencyFile,
                 dependency_set: Dependabot::FileParsers::Base::DependencySet,
                 dependency_tree: T::Hash[String, T.untyped]).void
        end
        def extract_dependencies_from_tree(pom, dependency_set, dependency_tree)
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
                file: nil,
                groups: groups,
                source: nil,
                metadata: {
                  packaging_type: type,
                  classifier: classifier,
                  pom_file: pom.name
                }
              }]
            )

            node["children"]&.each { |child| traverse_tree.call(child) }
          end

          traverse_tree.call(dependency_tree)
        end

        sig do
          params(dependency_files: T::Array[Dependabot::DependencyFile])
            .returns(Dependabot::FileParsers::Base::DependencySet)
        end
        def run_mvn_cli_dependency_tree(dependency_files)
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          # Copy only pom.xml files to a temporary directory to
          # output the dependency tree without building the project
          SharedHelpers.in_a_temporary_directory do |_path|
            dependency_files.each do |pom|
              pom_path = Pathname.new(pom.name).expand_path
              FileUtils.mkdir_p(File.dirname(pom_path))
              File.write(pom_path, pom.content)
            end

            stdout, stderr, status = Open3.capture3(
              "mvn dependency:tree -DoutputFile=dependency-tree-output.json -DoutputType=json -e"
            )
            raise "Failed to execute mvn dependency:tree: STDERR:#{stderr} STDOUT:#{stdout}" unless status.success?

            # mvn CLI outputs dependency tree for each pom.xml file, collect them
            # add into single dependency set
            dependency_files.each do |pom|
              pom_path = File.dirname(Pathname.new(pom.name).expand_path)
              output_file = File.join(pom_path, "dependency-tree-output.json")
              raise "Dependabot output file not found: #{output_file}!" unless File.exist?(output_file)

              dependency_tree = JSON.parse(File.read(output_file))
              extract_dependencies_from_tree(pom, dependency_set, dependency_tree)
            end
          end

          dependency_set
        end
      end
    end
  end
end
