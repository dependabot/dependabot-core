# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/shared_helpers"
require "dependabot/dependency_graphers/base"
require "dependabot/python/poetry_project"

module Dependabot
  module Python
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      # Builds graph entries from Poetry's own view of the lockfile. Poetry can
      # lock one package at several versions, each for a different
      # environment, so this emits an entry per locked version linked to the
      # child versions that install alongside it.
      class PoetryNativeGraph
        extend T::Sig

        PurlBuilder = T.type_alias { T.proc.params(dependency: Dependabot::Dependency).returns(String) }

        # Returns nil, so the caller graphs poetry.lock the existing way, when
        # the experiment is off or Poetry can't load the project.
        sig do
          params(
            pyproject: T.nilable(Dependabot::DependencyFile),
            lockfile: T.nilable(Dependabot::DependencyFile),
            dependency_names: T::Set[String],
            purl_builder: PurlBuilder
          ).returns(T.nilable(PoetryNativeGraph))
        end
        def self.build(pyproject:, lockfile:, dependency_names:, purl_builder:)
          return unless lockfile

          project = PoetryProject.load_if_enabled(pyproject: pyproject, lockfile: lockfile)
          return unless project

          new(project: project, dependency_names: dependency_names, purl_builder: purl_builder)
        end

        sig do
          params(
            project: PoetryProject,
            dependency_names: T::Set[String],
            purl_builder: PurlBuilder
          ).void
        end
        def initialize(project:, dependency_names:, purl_builder:)
          @project = project
          @dependency_names = dependency_names
          @purl_builder = purl_builder
        end

        # Returns nil when Poetry didn't lock the dependency from a package
        # index (for example git or path dependencies), so the caller can
        # graph it the usual way.
        sig do
          params(dependency: Dependabot::Dependency)
            .returns(T.nilable(T::Array[Dependabot::DependencyGraphers::ResolvedDependency]))
        end
        def resolved_for(dependency)
          locked = graphed_versions_of(dependency.name)
          return if locked.empty?

          locked.map do |package|
            Dependabot::DependencyGraphers::ResolvedDependency.new(
              package_url: purl(package.name, package.version),
              # TODO: a package declared for one environment and pulled in
              # transitively at another version for a different one is
              # reported as direct at both versions.
              direct: dependency.top_level?,
              runtime: package.production?,
              dependencies: package.dependencies.filter_map do |link|
                purl(link.name, link.version) if graphed?(link)
              end.uniq
            )
          end
        end

        private

        sig { returns(PoetryProject) }
        attr_reader :project

        sig { returns(T::Set[String]) }
        attr_reader :dependency_names

        sig { params(name: String).returns(T::Array[PoetryProject::LockedPackage]) }
        def graphed_versions_of(name)
          project.locked_versions_of(name).reject(&:direct_source?)
        end

        # Only link to versions that have their own entry in the graph.
        sig { params(link: PoetryProject::LockedLink).returns(T::Boolean) }
        def graphed?(link)
          return false unless dependency_names.include?(link.name)

          graphed_versions_of(link.name).any? { |package| package.version == link.version }
        end

        sig { params(name: String, version: String).returns(String) }
        def purl(name, version)
          @purl_builder.call(
            Dependabot::Dependency.new(name: name, version: version, requirements: [], package_manager: "pip")
          )
        end
      end
    end
  end
end
