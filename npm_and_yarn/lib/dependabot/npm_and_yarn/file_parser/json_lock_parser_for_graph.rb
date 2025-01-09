# typed: strict
# frozen_string_literal: true

require "json"
require "dependabot/dependency"
require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class JsonLockParserForGraph < Dependabot::NpmAndYarn::LockFileParserForGraph
      extend T::Sig

      LOCKFILE_V1 = 1
      LOCKFILE_V2 = 2
      LOCKFILE_V3 = 3

      VERSION_KEY = "version"
      LOCKFILE_VERSION_KEY = "lockfileVersion"
      LOCKFILE_DEPENDENCY_KEY = "dependencies"
      LOCKFILE_V2_AND_V3_DEPENDENCY_KEY = "packages"

      NODE_MODULES = "node_modules"

      sig { params(lockfile: DependencyFile).void }
      def initialize(lockfile)
        @lockfile = lockfile
      end

      sig do
        override.params(
          main_dependencies: T::Hash[String, Dependabot::Dependency]
        ).returns(DependencyGraph)
      end
      def build_dependency_graph(main_dependencies)
        lockfile_data, lockfile_version = parse

        dependency_graph = DependencyGraph.new

        # Create main dependency nodes with versions from lockfile
        main_nodes = main_dependencies.filter_map do |name, dependency|
          main_data = fetch_node_data(name, lockfile_data, lockfile_version)
          version = main_data&.fetch(VERSION_KEY, nil)
          next unless version

          dependency_graph.add_dependency(
            dependency: Dependabot::Dependency.new(
              name: name,
              version: version,
              package_manager: dependency.package_manager,
              requirements: dependency.requirements
            ),
            dependency_data: main_data
          )
        end

        # Add transitive dependencies for each main node
        main_nodes.each do |main_node|
          add_transitives(dependency_graph, main_node, lockfile_data, lockfile_version)
        end

        dependency_graph
      end

      private

      # Combines parsing and lock file version determination
      sig { returns([T::Hash[String, T::Hash[String, T.untyped]], Integer]) }
      def parse
        parsed_lockfile = JSON.parse(T.must(@lockfile.content))
        lockfile_version = parsed_lockfile[LOCKFILE_VERSION_KEY]&.to_i

        # Assume lockfile version 1 if the version is missing
        lockfile_version ||= LOCKFILE_V1

        lockfile_data =
          case lockfile_version
          when LOCKFILE_V2, LOCKFILE_V3
            parsed_lockfile[LOCKFILE_V2_AND_V3_DEPENDENCY_KEY] || {}
          when LOCKFILE_V1
            parsed_lockfile[LOCKFILE_DEPENDENCY_KEY] || {}
          else
            raise Dependabot::DependencyFileNotParseable, @lockfile.path
          end

        [lockfile_data, lockfile_version]
      end

      # Adds transitive dependencies for a given main dependency
      sig do
        params(
          dependency_graph: DependencyGraph,
          parent: DependencyNode,
          lockfile_data: T::Hash[String, T::Hash[String, T.untyped]],
          lockfile_version: Integer
        ).void
      end
      def add_transitives(dependency_graph, parent, lockfile_data, lockfile_version)
        node_data = parent.dependency_data

        return unless node_data

        dependencies_to_process = node_data[LOCKFILE_DEPENDENCY_KEY] || {}

        dependencies_to_process.each do |child_name, _|
          child_data = fetch_node_data(child_name, lockfile_data, lockfile_version)
          child_version = child_data&.fetch(VERSION_KEY, nil)

          next unless child_data && child_version

          # Avoid re-adding dependencies already linked as children
          existing_child = parent.child_by_name(child_name)
          next if existing_child

          child_node = dependency_graph.add_dependency(
            dependency: Dependabot::Dependency.new(
              name: child_name,
              version: child_version,
              package_manager: ECOSYSTEM,
              requirements: []
            ),
            dependency_data: child_data,
            parent_key: parent.key
          )
          next unless child_node

          add_transitives(dependency_graph, child_node, lockfile_data, lockfile_version)
        end
      end

      # Fetches node data for a dependency based on lockfile version
      sig do
        params(
          name: String, # dependency name
          lockfile_data: T::Hash[String, T::Hash[String, T.untyped]], # lockfile data
          lockfile_version: Integer # lockfile version
        ).returns(T.nilable(T::Hash[String, T.untyped]))
      end
      def fetch_node_data(name, lockfile_data, lockfile_version)
        if lockfile_version == LOCKFILE_V1
          lockfile_data[name]
        elsif [LOCKFILE_V2, LOCKFILE_V3].include?(lockfile_version)
          lockfile_data["#{NODE_MODULES}/#{name}"]
        end
      end
    end
  end
end
