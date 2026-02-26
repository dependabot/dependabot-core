# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_graphers"
require "dependabot/dependency_graphers/base"
require "dependabot/uv/file_parser"
require "toml-rb"

module Dependabot
  module Uv
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      UV_LOCK_COMMAND = T.let("pyenv exec uv lock --color never --no-progress && cat uv.lock", String)
      UV_TREE_COMMAND = T.let("pyenv exec uv tree -q --color never --no-progress --frozen", String)

      # Used to capture package lines from `uv tree` output.
      #
      # Example output:
      #   ├── flask v3.1.3
      #   │   ├── click v8.3.1
      #   │   └── jinja2 v3.1.6
      #   │       └── markupsafe v3.0.3
      #
      # The `prefix` contains tree-depth segments (`│   ` or `    `) and
      # `package` is the dependency name token before the `v<version>` marker.
      UV_TREE_LINE_REGEX = T.let(
        /^(?<prefix>(?:(?:│   )|(?:    ))*)(?:├──|└──)\s(?<package>.+?)\sv[^\s]+(?:\s+\(.*\))?$/,
        Regexp
      )

      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        # This cannot realistically happen as the parser will throw a runtime error
        # on init without a pyproject.toml file,
        # but this will avoid surprises if anything changes.
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

      # See UV tree docs https://docs.astral.sh/uv/reference/cli/#uv-tree
      # First try extracting relationships from uv.lock directly. If there is no
      # lockfile, generate one in a temporary parsed context and parse that.
      # If lockfile parsing fails for any reason, fall back to uv tree output.
      sig { returns(T::Hash[String, T::Array[String]]) }
      def fetch_package_relationships
        return package_relationships_from_lockfile(T.must(T.must(uv_lock).content)) if uv_lock

        begin
          Dependabot.logger.info("No uv.lock present, generating ephemeral lockfile for dependency graphing")
          generated_lockfile = uv_parser.run_in_parsed_context(UV_LOCK_COMMAND)
          return package_relationships_from_lockfile(generated_lockfile)
        rescue StandardError => e
          Dependabot.logger.warn("Failed to build dependency graph from uv.lock: #{e.message}")
          Dependabot.logger.info("Falling back to parsing uv tree output")
        end

        package_relationships_from_tree
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
        Dependabot.logger.warn("Failed to parse uv.lock relationships: #{e.message}")
        {}
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
            T.cast(package_data["dependencies"], T.nilable(T::Array[T.untyped])) || []
          else
            []
          end

        dependencies.filter_map do |dependency|
          dependency_name = lockfile_dependency_name(dependency)
          normalised_dependency_name(dependency_name) if dependency_name
        end
      end

      sig { params(dependency_data: T.untyped).returns(T.nilable(String)) }
      def lockfile_dependency_name(dependency_data)
        if dependency_data.is_a?(Hash)
          name = dependency_data["name"]
          return name if name.is_a?(String)
        end

        return dependency_data if dependency_data.is_a?(String)

        nil
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def package_relationships_from_tree
        relationship_stack = T.let([], T::Array[String])

        uv_parser.run_in_parsed_context(UV_TREE_COMMAND).lines.each_with_object({}) do |line, rels|
          match = line.match(UV_TREE_LINE_REGEX)
          next unless match

          package = normalised_dependency_name(T.must(match[:package]))
          depth = T.must(match[:prefix]).scan(/(?:│   |    )/).length

          relationship_stack[depth] = package
          relationship_stack.slice!(depth + 1, relationship_stack.length)

          parent = depth.zero? ? nil : relationship_stack[depth - 1]
          rels[package] ||= []
          next unless parent

          rels[parent] ||= []
          rels[parent] << package
        end
      end

      sig { returns(Dependabot::Uv::FileParser) }
      def uv_parser
        T.cast(file_parser, Dependabot::Uv::FileParser)
      end

      sig { params(name: String).returns(String) }
      def normalised_dependency_name(name)
        Dependabot::Uv::FileParser.normalize_dependency_name(name)
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
      def uv_lock
        return @uv_lock if defined?(@uv_lock)

        @uv_lock = T.let(
          dependency_files.find { |f| f.name == "uv.lock" },
          T.nilable(Dependabot::DependencyFile)
        )
      end
    end
  end
end

Dependabot::DependencyGraphers.register("uv", Dependabot::Uv::DependencyGrapher)
