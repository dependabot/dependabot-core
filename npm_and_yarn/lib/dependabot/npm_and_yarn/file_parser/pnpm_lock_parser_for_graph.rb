# typed: strict
# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/errors"
require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class PnpmLockParserForGraph < Dependabot::NpmAndYarn::LockFileParserForGraph
      extend T::Sig

      NAME_KEY = "name"
      VERSION_KEY = "version"
      DEPENDENCY_KEY = "dependencies"

      PNPM_PARSE_COMMAND = "pnpm:parseLockfile"

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
        lockfile_data = parse

        dependency_graph = DependencyGraph.new

        # Create main dependency nodes with versions from lockfile
        main_nodes = main_dependencies.filter_map do |name, dependency|
          main_entry = find_lockfile_entry(name, lockfile_data)
          version = main_entry&.fetch(VERSION_KEY, nil)
          next unless version

          dependency_graph.add_dependency(
            dependency: Dependabot::Dependency.new(
              name: name,
              version: version,
              package_manager: dependency.package_manager,
              requirements: dependency.requirements
            ),
            dependency_data: main_entry
          )
        end

        # Add transitive dependencies for each main node
        main_nodes.each do |main_node|
          add_transitives(dependency_graph, main_node, lockfile_data)
        end

        dependency_graph
      end

      private

      sig { returns(T::Array[T::Hash[String, T.untyped]]) }
      def parse
        # Return cached result if already defined
        @parse ||= T.let(
          begin
            SharedHelpers.in_a_temporary_directory do
              # Write the lockfile content to a temporary file
              File.write(PNPMPackageManager::NAME, @lockfile.content)

              # Run the subprocess to parse the lockfile
              result = SharedHelpers.run_helper_subprocess(
                command: NativeHelpers.helper_path,
                function: PNPM_PARSE_COMMAND,
                args: [Dir.pwd]
              )

              # Ensure result is an array of hashes, otherwise return an empty array
              if result.is_a?(Array) && result.all?(Hash)
                result
              else
                []
              end
            end
          rescue SharedHelpers::HelperSubprocessFailed
            # Handle subprocess failure by raising an appropriate error
            raise Dependabot::DependencyFileNotParseable, @lockfile.path
          end,
          T.nilable(T::Array[T::Hash[String, T.untyped]])
        )
      end

      sig do
        params(
          dependency_graph: DependencyGraph,
          parent: DependencyNode,
          lockfile_data: T::Array[T::Hash[String, T.untyped]]
        ).void
      end
      def add_transitives(dependency_graph, parent, lockfile_data)
        dependency_entry = parent.dependency_data
        return unless dependency_entry

        # Process transitive dependencies
        (dependency_entry[DEPENDENCY_KEY] || {}).each do |child_name, child_version|
          child_entry = lockfile_data.find do |entry|
            entry[NAME_KEY] == child_name && entry[VERSION_KEY] == child_version
          end

          # Skip if the child dependency is not found in the lockfile
          next unless child_entry

          # Avoid re-adding dependencies already linked as children
          existing_child = parent.child_by_name(child_name)
          next if existing_child

          child_node = dependency_graph.add_dependency(
            dependency: Dependabot::Dependency.new(
              name: child_name,
              version: child_version,
              package_manager: ECOSYSTEM,
              requirements: [] # Requirements are empty for transitive dependencies
            ),
            dependency_data: child_entry,
            parent_key: parent.key
          )
          next unless child_node

          add_transitives(dependency_graph, child_node, lockfile_data)
        end
      end

      sig do
        params(
          name: String,
          lockfile_data: T::Array[T::Hash[String, T.untyped]]
        ).returns(T.nilable(T::Hash[String, T.untyped]))
      end
      def find_lockfile_entry(name, lockfile_data)
        lockfile_data.find { |entry| entry[NAME_KEY] == name }
      end
    end
  end
end
