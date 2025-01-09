# typed: strict
# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/npm_and_yarn/file_parser/lockfile_parser_for_graph"
require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class YarnLockParserForGraph < Dependabot::NpmAndYarn::LockFileParserForGraph
      extend T::Sig

      VERSION_KEY = "version"
      DEPENDENCIES_KEY = "dependencies"

      sig { params(lockfile: DependencyFile).void }
      def initialize(lockfile)
        @lockfile = lockfile
      end

      sig do
        override.params(
          main_dependencies: T::Hash[String, Dependabot::Dependency]
        ).returns(Dependabot::DependencyGraph)
      end
      def build_dependency_graph(main_dependencies)
        lockfile_data = parse_lockfile

        dependency_graph = Dependabot::DependencyGraph.new

        # Create main dependency nodes with versions from lockfile
        main_nodes = main_dependencies.filter_map do |name, dependency|
          node_data = lockfile_data[name]
          version = node_data&.fetch(VERSION_KEY, nil)
          next unless version

          dependency_graph.add_dependency(
            dependency: Dependabot::Dependency.new(
              name: name,
              version: version,
              package_manager: dependency.package_manager,
              requirements: dependency.requirements
            ),
            dependency_data: node_data
          )
        end

        # Add transitive dependencies for each main node
        main_nodes.each do |main_node|
          add_transitives(dependency_graph, main_node, lockfile_data)
        end

        dependency_graph
      end

      private

      sig { returns(T::Hash[String, T.untyped]) }
      def parse_lockfile
        SharedHelpers.in_a_temporary_directory do
          File.write("yarn.lock", @lockfile.content)
          result = SharedHelpers.run_helper_subprocess(
            command: NativeHelpers.helper_path,
            function: "yarn:parseLockfile",
            args: [Dir.pwd]
          )
          T.cast(result, T::Hash[String, T.untyped])
        end
      rescue SharedHelpers::HelperSubprocessFailed => e
        raise Dependabot::DependencyFileNotParseable, e.message
      end

      sig do
        params(
          dependency_graph: Dependabot::DependencyGraph,
          parent: Dependabot::DependencyNode,
          lockfile_data: T::Hash[String, T.untyped]
        ).void
      end
      def add_transitives(dependency_graph, parent, lockfile_data)
        parent_data = parent.dependency_data
        return unless parent_data

        dependencies = parent_data[DEPENDENCIES_KEY] || {}

        dependencies.each do |child_name, _|
          child_data = lockfile_data[child_name]
          child_version = child_data&.fetch(VERSION_KEY, nil)

          next unless child_data && child_version

          # Avoid re-adding dependencies already linked as children
          existing_child = parent.child_by_name(child_name)
          next if existing_child

          child_node = dependency_graph.add_dependency(
            dependency: Dependabot::Dependency.new(
              name: child_name,
              version: child_version,
              package_manager: "yarn",
              requirements: []
            ),
            dependency_data: child_data,
            parent_key: parent.key
          )
          next unless child_node

          add_transitives(dependency_graph, child_node, lockfile_data)
        end
      end
    end
  end
end
