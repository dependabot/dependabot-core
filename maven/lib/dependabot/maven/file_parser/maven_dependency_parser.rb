# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/maven/file_parser"
require "dependabot/maven/native_helpers"

module Dependabot
  module Maven
    class FileParser
      class MavenDependencyParser
        extend T::Sig
        require "dependabot/file_parsers/base/dependency_set"

        DEPENDENCY_OUTPUT_FILE = "dependency-tree-output.json"

        sig do
          params(dependency_files: T::Array[Dependabot::DependencyFile])
            .returns(Dependabot::FileParsers::Base::DependencySet)
        end
        def self.build_dependency_set(dependency_files)
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
              File.write(pom_path, pom.content)
            end

            Dir.chdir(project_directory) do
              NativeHelpers.run_mvn_dependency_tree_plugin(DEPENDENCY_OUTPUT_FILE)
            end

            # mvn CLI outputs dependency tree for each pom.xml file, collect them
            # add into single dependency set
            dependency_files.each do |pom|
              pom_path = File.join(project_directory, pom.name)
              pom_dir = File.dirname(pom_path)
              output_file = File.join(pom_dir, DEPENDENCY_OUTPUT_FILE)

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

        sig do
          params(pom: Dependabot::DependencyFile,
                 dependency_set: Dependabot::FileParsers::Base::DependencySet,
                 dependency_tree: T::Hash[String, T.untyped]).void
        end
        def self.extract_dependencies_from_tree(pom, dependency_set, dependency_tree)
          traverse_tree = T.let(-> {}, T.proc.params(node: T::Hash[String, T.untyped]).void)
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
              }],
              origin_files: [pom.name]
            )

            node["children"]&.each(&traverse_tree)
          end

          traverse_tree.call(dependency_tree)
        end

        sig do
          params(dependency_files: T::Array[Dependabot::DependencyFile], temp_path: String)
            .returns(String)
        end
        def self.create_directory_structure(dependency_files, temp_path)
          # Find the topmost directory level by finding the minimum number of "../" sequences
          relative_top_depth = dependency_files.map do |pom|
            Pathname.new(pom.name).cleanpath.to_s.scan("../").length
          end.max || 0

          # Create the base directory structure with the required depth
          base_depth_path = (0...relative_top_depth).reduce(temp_path) do |path, i|
            File.join(path, "l#{i}")
          end

          FileUtils.mkdir_p(base_depth_path)

          base_depth_path
        end
      end
    end
  end
end
