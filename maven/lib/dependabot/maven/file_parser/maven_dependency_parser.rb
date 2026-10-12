# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/dependency_requirement"
require "dependabot/maven/file_parser"
require "dependabot/maven/native_helpers"
require "dependabot/maven/file_parser/repositories_finder"
require "dependabot/maven/shared/maven_settings"

module Dependabot
  module Maven
    class FileParser
      # The `mvn dependency:tree` scan: runs Maven, reads its JSON output into
      # dependencies, and merges them with the XML-declared requirements.
      class MavenDependencyParser
        extend T::Sig

        require "dependabot/file_parsers/base/dependency_set"

        DEPENDENCY_OUTPUT_FILE = "dependency-tree-output.json"
        REGISTRY_MIRROR_ID = "dependabot-registry-mirror"

        # Runs `mvn dependency:tree` and returns every resolved dependency, or nil when the
        # scan fails so the caller can fall back to the XML-only parse.
        sig do
          params(
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          ).returns(T.nilable(Dependabot::FileParsers::Base::DependencySet))
        end
        def self.build_dependency_set(dependency_files, credentials: [])
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          # Copy only pom.xml files to a temporary directory to
          # output the dependency tree without building the project
          SharedHelpers.in_a_temporary_directory do |temp_path|
            # Create a directory structure that maintains relative relationships
            project_directory = create_directory_structure(dependency_files, temp_path.to_s)

            dependency_files.each do |pom|
              pom_path = File.join(project_directory, pom.name)
              FileUtils.mkdir_p(File.dirname(pom_path))
              File.write(pom_path, pom.content)
            end

            Dir.chdir(project_directory) { run_scan(credentials) }

            # mvn CLI outputs dependency tree for each pom.xml file, collect them
            # add into single dependency set
            dependency_files.each do |pom|
              output_file = File.join(File.dirname(File.join(project_directory, pom.name)), DEPENDENCY_OUTPUT_FILE)

              # If we run updater from sub-module, parent file might be included in dependency files,
              # but mvn CLI will not generate dependency tree for it unless we start from the parent.
              # In that case we can just skip it and focus only on current file and it's sub-modules.
              next unless File.exist?(output_file)

              add_tree(dependency_set, pom, JSON.parse(File.read(output_file)))
            end
          end

          dependency_set
        rescue StandardError => e
          # Never fail the job or log Maven output (it can include registry URLs) from here.
          Dependabot.logger.warn("Maven dependency tree scan failed (#{e.class}); using declared dependencies only")
          nil
        end

        # Merges the requirements of one dependency found by both the XML parse and the scan.
        #
        # Each declared (XML) requirement is paired with the scanned requirement from the same
        # POM. The XML keeps its requirement, file, groups and source, because the file updater
        # matches them against the XML node; the scan only adds metadata Maven resolved.
        # Scanned requirements with no declaration in that POM (inherited or transitive) are
        # kept as they are.
        sig do
          params(requirements: T::Array[Dependabot::DependencyRequirement])
            .returns(T::Array[Dependabot::DependencyRequirement])
        end
        def self.merge_requirements(requirements)
          declared, scanned = requirements.partition(&:file)
          merged = declared.map do |declared_req|
            index = scanned.index { |req| req.metadata_string("pom_file") == declared_req.file }
            index ? merge_requirement_pair(declared_req, T.must(scanned.delete_at(index))) : declared_req
          end
          merged + scanned
        end

        # Uses the job's registries the same way Dependabot's own Maven lookups do: a
        # `replaces-base` registry stands in for Central, and other registries are added.
        # Repositories declared in the POMs are left to Maven.
        sig { params(credentials: T::Array[Dependabot::Credential]).void }
        def self.run_scan(credentials)
          finder = RepositoriesFinder.new(pom_fetcher: nil, credentials: credentials)
          base_url = finder.replaces_base_url&.strip&.chomp("/")
          mirror = base_url && Shared::MavenSettings::Mirror.new(
            id: REGISTRY_MIRROR_ID, url: base_url, mirror_of: RepositoriesFinder::CENTRAL_REPO_ID
          )

          NativeHelpers.run_mvn_dependency_tree_plugin(
            DEPENDENCY_OUTPUT_FILE,
            mirror: mirror,
            repository_urls: finder.urls_from_credentials - [base_url]
          )
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

        # The root node is the module itself and is skipped. Depth-one nodes are direct
        # dependencies, including ones inherited from a parent POM. Deeper nodes are
        # transitive and record the dependency that pulled them in as `pulled_in_by`.
        sig do
          params(
            dependency_set: Dependabot::FileParsers::Base::DependencySet,
            pom: Dependabot::DependencyFile,
            tree: Object
          ).void
        end
        def self.add_tree(dependency_set, pom, tree)
          tree_children(tree).each { |node| add_tree_node(dependency_set, pom, node, pulled_in_by: nil) }
        end
        private_class_method :add_tree

        sig do
          params(
            dependency_set: Dependabot::FileParsers::Base::DependencySet,
            pom: Dependabot::DependencyFile,
            node: T::Hash[String, Object],
            pulled_in_by: T.nilable(String)
          ).void
        end
        def self.add_tree_node(dependency_set, pom, node, pulled_in_by:)
          group_id = node_string(node, "groupId")
          artifact_id = node_string(node, "artifactId")
          version = node_string(node, "version")
          return unless group_id && artifact_id && version

          name = "#{group_id}:#{artifact_id}"
          scope = node_string(node, "scope")
          dependency_set << Dependabot::Dependency.new(
            name: name,
            version: version,
            package_manager: "maven",
            requirements: [{
              # Transitive dependencies keep this "declared-looking" shape on purpose:
              # the file updater pins them through `pom_file` (see FileUpdater).
              requirement: version,
              file: nil,
              groups: scope == "test" ? ["test"] : [],
              source: nil,
              metadata: {
                packaging_type: node_string(node, "type"),
                classifier: node_string(node, "classifier"),
                scope: scope,
                pom_file: pom.name,
                pulled_in_by: pulled_in_by
              }.compact
            }]
          )

          tree_children(node).each { |child| add_tree_node(dependency_set, pom, child, pulled_in_by: name) }
        end
        private_class_method :add_tree_node

        sig { params(node: Object).returns(T::Array[T::Hash[String, Object]]) }
        def self.tree_children(node)
          return [] unless node.is_a?(Hash)

          value = node["children"]
          value.is_a?(Array) ? value.grep(Hash) : []
        end
        private_class_method :tree_children

        sig { params(node: T::Hash[String, Object], key: String).returns(T.nilable(String)) }
        def self.node_string(node, key)
          value = node[key]
          value.is_a?(String) && !value.empty? ? value : nil
        end
        private_class_method :node_string

        sig do
          params(
            declared: Dependabot::DependencyRequirement,
            scanned: Dependabot::DependencyRequirement
          ).returns(Dependabot::DependencyRequirement)
        end
        def self.merge_requirement_pair(declared, scanned)
          declared_metadata = declared.metadata || {}
          metadata = (scanned.metadata || {}).merge(declared_metadata) { |_key, scan, xml| xml.nil? ? scan : xml }

          Dependabot::DependencyRequirement.create(
            requirement: declared.requirement,
            file: declared.file,
            groups: declared.groups,
            source: declared.source,
            metadata: metadata
          )
        end
        private_class_method :merge_requirement_pair
      end
    end
  end
end
