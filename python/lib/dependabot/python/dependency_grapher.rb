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

      sig { returns(T::Hash[String, T::Array[String]]) }
      def fetch_package_relationships
        return package_relationships_from_lockfile(T.must(T.must(poetry_lock).content)) if poetry_lock

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
            T.cast(package_data["dependencies"], T.nilable(T::Hash[String, T.untyped])) || {}
          else
            {}
          end

        dependencies.keys.filter_map do |dependency_name|
          normalised_dependency_name(dependency_name)
        end
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
