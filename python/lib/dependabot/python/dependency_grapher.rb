# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_graphers"
require "dependabot/dependency_graphers/base"
require "dependabot/python/file_parser"
require "dependabot/python/name_normaliser"
require "toml-rb"

module Dependabot
  module Python
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      POETRY_SHOW_TREE_COMMAND = T.let(
        "pyenv exec poetry show --tree --no-ansi --no-interaction",
        String
      )

      # Used to capture the top-level package header from `poetry show --tree` output.
      #
      # Example:
      #   flask 3.1.3 A simple framework for building complex web applications.
      #
      # Captures the package name token before the version.
      POETRY_TREE_HEADER_REGEX = T.let(
        /^(?<package>\S+)\s+\S+\s/,
        Regexp
      )

      # Used to capture child dependency lines from `poetry show --tree` output.
      #
      # Example:
      #   ├── blinker >=1.9
      #   │   └── markupsafe >=2.0
      #
      # The `prefix` contains tree-depth segments (`│   ` or `    `) and
      # `package` is the dependency name token before the version constraint.
      POETRY_TREE_LINE_REGEX = T.let(
        /^(?<prefix>(?:(?:│   )|(?:    ))*)(?:├──|└──)\s(?<package>\S+)\s/,
        Regexp
      )

      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        raise DependabotError, "No pyproject.toml present in dependency files." unless pyproject_toml

        T.must(pyproject_toml)
      end

      private

      sig { override.params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def fetch_subdependencies(dependency)
        dependency_names = @dependencies.map(&:name)
        package_relationships.fetch(dependency.name, []).select { |child| dependency_names.include?(child) }
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def package_relationships
        @package_relationships ||= T.let(
          fetch_package_relationships,
          T.nilable(T::Hash[String, T::Array[String]])
        )
      end

      # First try extracting relationships from poetry.lock directly.
      # If there is no lockfile, fall back to parsing `poetry show --tree` output.
      sig { returns(T::Hash[String, T::Array[String]]) }
      def fetch_package_relationships
        return package_relationships_from_lockfile(T.must(T.must(poetry_lock).content)) if poetry_lock

        package_relationships_from_tree
      rescue StandardError => e
        Dependabot.logger.warn("Failed to build dependency graph: #{e.message}")
        {}
      end

      sig { params(lockfile_content: String).returns(T::Hash[String, T::Array[String]]) }
      def package_relationships_from_lockfile(lockfile_content)
        lockfile_packages(lockfile_content).each_with_object({}) do |package_data, rels|
          parent = lockfile_parent_name(package_data)
          next unless parent

          rels[parent] ||= []
          rels[parent].concat(lockfile_child_names(package_data))
        end
      rescue StandardError => e
        Dependabot.logger.warn("Failed to parse poetry.lock relationships: #{e.message}")
        Dependabot.logger.info("Falling back to parsing poetry show --tree output")
        package_relationships_from_tree
      end

      sig { params(lockfile_content: String).returns(T::Array[T.untyped]) }
      def lockfile_packages(lockfile_content)
        parsed = TomlRB.parse(lockfile_content)
        T.cast(parsed.fetch("package", []), T::Array[T.untyped])
      end

      sig { params(package_data: T.untyped).returns(T.nilable(String)) }
      def lockfile_parent_name(package_data)
        return unless package_data.is_a?(Hash)

        package_name = package_data["name"]
        return unless package_name.is_a?(String)

        normalised_dependency_name(package_name)
      end

      sig { params(package_data: T.untyped).returns(T::Array[String]) }
      def lockfile_child_names(package_data)
        dependencies =
          if package_data.is_a?(Hash)
            T.cast(package_data["dependencies"], T.nilable(T::Hash[String, T.untyped])) || {}
          else
            {}
          end

        dependencies.keys.filter_map do |dependency_name|
          normalised_dependency_name(dependency_name)
        end
      end

      # Parse `poetry show --tree` output into parent→children relationships.
      #
      # The output has a distinct format from `uv tree`:
      # - Each top-level dependency starts a new block with: `name version description`
      # - Child dependencies use tree characters: `├──`, `└──`, `│`
      # - Blocks are separated by blank lines
      sig { returns(T::Hash[String, T::Array[String]]) }
      def package_relationships_from_tree
        Dependabot.logger.info("Parsing poetry show --tree output for dependency graphing")
        relationship_stack = T.let([], T::Array[String])

        python_parser.run_in_parsed_context(POETRY_SHOW_TREE_COMMAND).lines.each_with_object({}) do |line, rels|
          header_match = line.match(POETRY_TREE_HEADER_REGEX)
          child_match = line.match(POETRY_TREE_LINE_REGEX)

          if header_match && !child_match
            relationship_stack = process_tree_header(header_match, rels)
          elsif child_match
            process_tree_child(child_match, relationship_stack, rels)
          end
        end
      end

      sig do
        params(
          match: MatchData,
          rels: T::Hash[String, T::Array[String]]
        ).returns(T::Array[String])
      end
      def process_tree_header(match, rels)
        root = normalised_dependency_name(T.must(match[:package]))
        rels[root] ||= []
        [root]
      end

      sig do
        params(
          match: MatchData,
          relationship_stack: T::Array[String],
          rels: T::Hash[String, T::Array[String]]
        ).void
      end
      def process_tree_child(match, relationship_stack, rels)
        package = normalised_dependency_name(T.must(match[:package]))
        depth = T.must(match[:prefix]).scan(/(?:│   |    )/).length + 1

        relationship_stack[depth] = package
        relationship_stack.slice!(depth + 1, relationship_stack.length)

        parent = relationship_stack[depth - 1]
        rels[package] ||= []
        return unless parent

        rels[parent] ||= []
        rels[parent] << package
      end

      sig { returns(Dependabot::Python::FileParser) }
      def python_parser
        T.cast(file_parser, Dependabot::Python::FileParser)
      end

      sig { params(name: String).returns(String) }
      def normalised_dependency_name(name)
        NameNormaliser.normalise(name)
      end

      sig { override.params(_dependency: Dependabot::Dependency).returns(String) }
      def purl_pkg_for(_dependency)
        "pypi"
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pyproject_toml
        return @pyproject_toml if defined?(@pyproject_toml)

        @pyproject_toml = T.let(
          dependency_files.find { |f| f.name == "pyproject.toml" },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def poetry_lock
        return @poetry_lock if defined?(@poetry_lock)

        @poetry_lock = T.let(
          dependency_files.find { |f| f.name == "poetry.lock" },
          T.nilable(Dependabot::DependencyFile)
        )
      end
    end
  end
end

Dependabot::DependencyGraphers.register("pip", Dependabot::Python::DependencyGrapher)
