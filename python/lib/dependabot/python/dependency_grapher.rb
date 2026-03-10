# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/dependency_graphers"
require "dependabot/dependency_graphers/base"
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
        %w[default develop].each_with_object({}) do |section, rels|
          section_data = parsed_pipfile_lock[section]
          next unless section_data.is_a?(Hash)

          section_data.each do |name, details|
            next unless details.is_a?(Hash)

            parent = NameNormaliser.normalise(name)
            depends = details["depends"]
            depends = [] unless depends.is_a?(Array)
            rels[parent] = depends.map { |dep| NameNormaliser.normalise(dep) }
          end
        end
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def parsed_pipfile_lock
        @parsed_pipfile_lock ||= T.let(
          JSON.parse(T.must(pipfile_lock).content),
          T.nilable(T::Hash[String, T.untyped])
        )
      rescue JSON::ParserError
        raise Dependabot::DependencyFileNotParseable, T.must(pipfile_lock).name
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
