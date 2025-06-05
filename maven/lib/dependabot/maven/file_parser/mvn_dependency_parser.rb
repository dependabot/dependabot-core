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
          SharedHelpers.in_a_temporary_directory do |temp_path|
            # Create a directory structure that maintains relative relationships
            project_directory = create_directory_structure(dependency_files, temp_path.to_s)

            dependency_files.each do |pom|
              pom_path = File.join(project_directory, pom.name)
              pom_dir = File.dirname(pom_path)
              FileUtils.mkdir_p(pom_dir)
              Dependabot.logger.info("Writing pom file to a path: #{pom_path}")
              File.write(pom_path, pom.content)
            end

            Dir.chdir(project_directory) do
              stdout, stderr, status = Open3.capture3(
                "mvn dependency:tree -DoutputFile=dependency-tree-output.json -DoutputType=json -e"
              )
              Dependabot.logger.info("mvn dependency:tree output: STDOUT:#{stdout} STDERR:#{stderr}")
              raise "Failed to execute mvn dependency:tree: STDERR:#{stderr} STDOUT:#{stdout}" unless status.success?
            end

            # mvn CLI outputs dependency tree for each pom.xml file, collect them
            # add into single dependency set
            dependency_files.each do |pom|
              pom_path = File.join(project_directory, pom.name)
              pom_dir = File.dirname(pom_path)
              output_file = File.join(pom_dir, "dependency-tree-output.json")

              Dependabot.logger.info("Reading dependency tree output from: #{output_file}")

              # If we run updater from sub-module, parent file might be included in dependency files,
              # but mvn CLI will not generate dependency tree for it unless we start from the parent.
              # In that case we can just skip it and focus only on current file and it's sub-modules.
              unless File.exist?(output_file)
                Dependabot.logger.warn("Dependency tree output file not found: #{output_file}")
                next
              end

              dependency_tree = JSON.parse(File.read(output_file))
              extract_dependencies_from_tree(pom, dependency_set, dependency_tree)
            end
          end

          dependency_set
        end

        private

        sig do
          params(dependency_files: T::Array[Dependabot::DependencyFile], temp_path: String)
            .returns(String)
        end
        def create_directory_structure(dependency_files, temp_path)
          # Find the topmost directory level by finding the minimum number of "../" sequences
          relative_top_depth = 0
          dependency_files.each do |pom|
            depth = pom.name.scan("../").length
            relative_top_depth = [relative_top_depth, depth].max
          end

          # Create the base directory structure with the required depth
          base_depth_path = temp_path
          relative_top_depth.times do |i|
            base_depth_path = File.join(base_depth_path, "l#{i}")
          end

          FileUtils.mkdir_p(base_depth_path)

          base_depth_path
        end
      end
    end
  end
end
