# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/dependency_graphers"
require "dependabot/dependency_graphers/base"
require "dependabot/python/file_parser"
require "dependabot/python/name_normaliser"
require "toml-rb"

module Dependabot
  module Python
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        if pyproject_toml
          # Poetry/pyproject.toml project: prefer poetry.lock lockfile when available
          T.must(poetry_lock || pyproject_toml)
        elsif pipfile
          # Pipenv project: prefer Pipfile.lock lockfile when available
          T.must(pipfile_lock || pipfile)
        else
          raise DependabotError, "No pyproject.toml or Pipfile present in dependency files."
        end
      end

      private

      sig { override.params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def fetch_subdependencies(dependency)
        package_relationships.fetch(dependency.name, []).select { |child| dependency_name_set.include?(child) }
      end

      sig { override.params(_dependency: Dependabot::Dependency).returns(String) }
      def purl_pkg_for(_dependency)
        "pypi"
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def package_relationships
        @package_relationships ||= T.let(
          fetch_package_relationships,
          T.nilable(T::Hash[String, T::Array[String]])
        )
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def fetch_package_relationships
        if poetry_lock
          fetch_poetry_lock_relationships
        elsif pipfile_lock
          fetch_pipfile_lock_relationships
        else
          {}
        end
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def fetch_poetry_lock_relationships
        TomlRB.parse(T.must(poetry_lock).content).fetch("package", []).each_with_object({}) do |pkg, rels|
          next unless pkg.is_a?(Hash) && pkg["name"].is_a?(String)

          parent = NameNormaliser.normalise(pkg["name"])
          deps = pkg["dependencies"]
          deps = {} unless deps.is_a?(Hash)
          children = deps.keys.map { |name| NameNormaliser.normalise(name) }
          rels[parent] = children
        end
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
        raise Dependabot::DependencyFileNotParseable, T.must(poetry_lock).name
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def fetch_pipfile_lock_relationships
        json_output = T.cast(file_parser, Python::FileParser).run_pipenv_graph
        parse_pipenv_graph_output(json_output)
      end

      # Parses the JSON output from `pipenv graph --json`.
      #
      # The format is a flat list where each entry has a "package" object and a "dependencies" array:
      #   [
      #     {
      #       "package": { "package_name": "requests", "installed_version": "2.32.5", ... },
      #       "dependencies": [
      #         { "package_name": "certifi", "installed_version": "2024.2.2", ... },
      #         ...
      #       ]
      #     },
      #     ...
      #   ]
      sig { params(json_output: String).returns(T::Hash[String, T::Array[String]]) }
      def parse_pipenv_graph_output(json_output)
        JSON.parse(json_output).each_with_object({}) do |entry, rels|
          next unless entry.is_a?(Hash)

          pkg = entry["package"]
          next unless pkg.is_a?(Hash) && pkg["package_name"].is_a?(String)

          parent = NameNormaliser.normalise(pkg["package_name"])
          deps = entry["dependencies"]
          deps = [] unless deps.is_a?(Array)
          children = deps.filter_map do |dep|
            next unless dep.is_a?(Hash) && dep["package_name"].is_a?(String)

            NameNormaliser.normalise(dep["package_name"])
          end
          rels[parent] = children
        end
      rescue JSON::ParserError
        Dependabot.logger.warn("Unexpected output from 'pipenv graph --json': could not parse as JSON")
        {}
      end

      sig { returns(T::Set[String]) }
      def dependency_name_set
        @dependency_name_set ||= T.let(
          Set.new(@dependencies.map(&:name)),
          T.nilable(T::Set[String])
        )
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

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pipfile
        return @pipfile if defined?(@pipfile)

        @pipfile = T.let(
          dependency_files.find { |f| f.name == "Pipfile" },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pipfile_lock
        return @pipfile_lock if defined?(@pipfile_lock)

        @pipfile_lock = T.let(
          dependency_files.find { |f| f.name == "Pipfile.lock" },
          T.nilable(Dependabot::DependencyFile)
        )
      end
    end
  end
end

Dependabot::DependencyGraphers.register("pip", Dependabot::Python::DependencyGrapher)
