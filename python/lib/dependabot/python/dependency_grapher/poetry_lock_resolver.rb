# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/dependency_graphers/base"
require "dependabot/python/file_parser/poetry_lock"
require "dependabot/python/name_normaliser"

module Dependabot
  module Python
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      # Poetry can lock one package at several versions, each behind its own environment marker (for example, one
      # version per Python version range). The file parser keeps one version per package name, so this resolves
      # every version that the lockfile pins, and links each one to the packages that it depends on.
      class PoetryLockResolver
        extend T::Sig

        sig { params(lockfile: Dependabot::DependencyFile).void }
        def initialize(lockfile)
          packages = FileParser::PoetryLock.from_file(lockfile).packages

          @versions_by_name = T.let(versions_by_name(packages), T::Hash[String, T::Array[String]])
          @child_names_by_package = T.let(
            child_names_by_package(packages),
            T::Hash[String, T::Hash[String, T::Array[String]]]
          )
        end

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            with_subdependencies: T::Boolean,
            purl_for: T.proc.params(dependency: Dependabot::Dependency).returns(String)
          ).returns(T::Hash[String, Dependabot::DependencyGraphers::ResolvedDependency])
        end
        def resolved_dependencies(dependencies, with_subdependencies:, &purl_for)
          dependencies_by_name = dependencies.to_h { |dependency| [dependency.name, dependency] }

          dependencies.each_with_object({}) do |dependency, resolved|
            locked_versions_of(dependency).each do |locked_dependency|
              purl = yield(locked_dependency)
              children = with_subdependencies ? locked_children_of(locked_dependency, dependencies_by_name) : []

              resolved[purl] = Dependabot::DependencyGraphers::ResolvedDependency.new(
                package_url: purl,
                direct: dependency.top_level?,
                runtime: dependency.production?,
                dependencies: children.map(&purl_for).uniq
              )
            end
          end
        end

        private

        # Returns one copy of the dependency for each version that the lockfile pins. Returns the dependency itself
        # when the lockfile pins only one version of it, or does not pin the version that the parser selected.
        sig { params(dependency: Dependabot::Dependency).returns(T::Array[Dependabot::Dependency]) }
        def locked_versions_of(dependency)
          versions = @versions_by_name.fetch(dependency.name, [])
          return [dependency] unless versions.length > 1 && versions.include?(dependency.version)

          versions.map do |version|
            Dependabot::Dependency.new(
              name: dependency.name,
              version: version,
              requirements: dependency.requirements,
              package_manager: dependency.package_manager,
              metadata: dependency.metadata,
              subdependency_metadata: dependency.subdependency_metadata
            )
          end
        end

        # A package can depend on a package that is locked at several versions. We link it to every version
        # because each version applies to a different environment.
        sig do
          params(
            dependency: Dependabot::Dependency,
            dependencies_by_name: T::Hash[String, Dependabot::Dependency]
          ).returns(T::Array[Dependabot::Dependency])
        end
        def locked_children_of(dependency, dependencies_by_name)
          version = dependency.version
          return [] if version.nil?

          @child_names_by_package.fetch(dependency.name, {}).fetch(version, []).flat_map do |child_name|
            child = dependencies_by_name[child_name]
            child ? locked_versions_of(child) : []
          end
        end

        sig do
          params(packages: T::Array[FileParser::PoetryLock::Package]).returns(T::Hash[String, T::Array[String]])
        end
        def versions_by_name(packages)
          versions = T.let({}, T::Hash[String, T::Array[String]])
          packages.each do |package|
            name = NameNormaliser.normalise(package.name)
            versions[name] = versions.fetch(name, []) | [package.version]
          end
          versions
        end

        sig do
          params(packages: T::Array[FileParser::PoetryLock::Package])
            .returns(T::Hash[String, T::Hash[String, T::Array[String]]])
        end
        def child_names_by_package(packages)
          child_names = T.let({}, T::Hash[String, T::Hash[String, T::Array[String]]])
          packages.each do |package|
            name = NameNormaliser.normalise(package.name)
            child_names_by_version = child_names.fetch(name, {})
            child_names_by_version[package.version] =
              package.dependency_names.map { |child_name| NameNormaliser.normalise(child_name) }
            child_names[name] = child_names_by_version
          end
          child_names
        end
      end
    end
  end
end
