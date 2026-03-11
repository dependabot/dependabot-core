# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/dependency_graphers"
require "dependabot/dependency_graphers/base"
require "dependabot/python/file_parser"
require "dependabot/python/language_version_manager"
require "dependabot/python/name_normaliser"
require "dependabot/python/pipenv_runner"
require "toml-rb"

module Dependabot
  module Python
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        dependency_files_by_package_manager = T.let(
          {
            PipenvPackageManager::NAME => [pipfile_lock, pipfile],
            PoetryPackageManager::NAME => [poetry_lock, pyproject_toml],
            PipCompilePackageManager::NAME => [pyproject_toml, pipfile_lock, pipfile],
            PipPackageManager::NAME => [pyproject_toml, pipfile_lock, pipfile]
          },
          T::Hash[String, T::Array[T.nilable(Dependabot::DependencyFile)]]
        )

        candidates = dependency_files_by_package_manager[python_package_manager]
        raise DependabotError, "No pyproject.toml or Pipfile present in dependency files." unless candidates

        relevant_file = candidates.compact.first
        return relevant_file if relevant_file

        raise DependabotError, "No pyproject.toml or Pipfile present in dependency files."
      end

      private

      sig { returns(String) }
      def python_package_manager
        T.must(file_parser.ecosystem).package_manager.name
      end

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
        json_output = pipenv_runner.run_pipenv_graph
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

      sig { returns(PipenvRunner) }
      def pipenv_runner
        @pipenv_runner ||= T.let(
          PipenvRunner.new(
            dependency: nil,
            lockfile: pipfile_lock,
            language_version_manager: language_version_manager,
            dependency_files: dependency_files
          ),
          T.nilable(PipenvRunner)
        )
      end

      sig { returns(LanguageVersionManager) }
      def language_version_manager
        @language_version_manager ||= T.let(
          LanguageVersionManager.new(
            python_requirement_parser: python_requirement_parser
          ),
          T.nilable(LanguageVersionManager)
        )
      end

      sig { returns(FileParser::PythonRequirementParser) }
      def python_requirement_parser
        @python_requirement_parser ||= T.let(
          FileParser::PythonRequirementParser.new(
            dependency_files: dependency_files
          ),
          T.nilable(FileParser::PythonRequirementParser)
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
