# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module DependencyGrapher
    extend T::Sig

    class Base
      extend T::Sig
      extend T::Helpers

      abstract!

      # TODO: Add credentials to init in future.
      #
      # The grapher will be responsible for additional native commands in cases where we need to do further
      # dependency file inspection, some binaries may try to authenticate with package registries as part
      # of these operations, such as pipenv.
      #
      # We should pass in these credentials by default the first time we need to do this but we can defer
      # this until then since rollout of dependency hierarchies is a separate concern.
      sig do
        params(
          dependency_files: T::Array[Dependabot::DependencyFile],
          dependencies: T::Array[Dependabot::Dependency]
        ).void
      end
      def initialize(dependency_files:, dependencies:)
        @dependency_files = dependency_files
        @dependencies = dependencies
      end

      # Each grapher must implement a heuristic to determine which dependency file should be used as the owner
      # of the resolved_dependencies.
      #
      # Conventionally, this is the lockfile for the file set but some parses may only include the manifest
      # so this method should take into account the correct priority based on which files were parsed.
      sig { abstract.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file; end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def resolved_dependencies
        @dependencies.each_with_object({}) do |dep, resolved|
          resolved[dep.name] = {
            package_url: build_purl(dep),
            relationship: relationship_for(dep),
            scope: scope_for(dep),
            # We expect direct dependencies to be added to the metadata, but they may not always be available
            dependencies: fetch_parent_dependencies(dep),
            metadata: {}
          }
        end
      end

      private

      # Each grapher is expected to implement a method to look up the parents of a given dependency.
      #
      # The strategy that should be used is highly dependent on the ecosystem, in some cases the parser
      # may be able to set this information in the dependency.metadata collection, in others the grapher
      # will need to run additional native commands.
      sig { abstract.params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def fetch_parent_dependencies(dependency); end

      sig { params(dependency: Dependabot::Dependency).returns(String) }
      def build_purl(dependency)
        "pkg:#{purl_pkg_for(dependency.package_manager)}/#{dependency.name}@#{dependency.version}".chomp("@")
      end

      # TODO: Delegate this to ecosystem-specific base classes
      sig { params(package_manager: String).returns(String) }
      def purl_pkg_for(package_manager)
        case package_manager
        when "bundler"
          "gem"
        when "npm_and_yarn", "bun"
          "npm"
        when "maven", "gradle"
          "maven"
        when "pip", "uv"
          "pypi"
        when "cargo"
          "cargo"
        when "hex"
          "hex"
        when "composer"
          "composer"
        when "nuget"
          "nuget"
        when "go_modules"
          "golang"
        when "docker"
          "docker"
        when "github_actions"
          "github"
        when "terraform"
          "terraform"
        when "pub"
          "pub"
        when "elm"
          "elm"
        else
          "generic"
        end
      end

      sig { params(dep: Dependabot::Dependency).returns(String) }
      def relationship_for(dep)
        if dep.top_level?
          "direct"
        else
          "indirect"
        end
      end

      sig { params(dependency: Dependabot::Dependency).returns(String) }
      def scope_for(dependency)
        if dependency.production?
          "runtime"
        else
          "development"
        end
      end
    end

    class Generic < Base
      extend T::Sig
      extend T::Helpers

      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        T.must(filtered_dependency_files.last)
      end

      private

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def filtered_dependency_files
        @dependency_files.reject { |f| f.support_file? || f.vendored_file? }
      end

      sig { override.params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def fetch_parent_dependencies(dependency)
        dependency.metadata.fetch(:depends_on, [])
      end
    end

    @graphers = T.let({}, T::Hash[String, T.class_of(Base)])

    sig { params(package_manager: String).returns(T.class_of(Base)) }
    def self.for_package_manager(package_manager)
      grapher = @graphers[package_manager]
      return grapher if grapher

      # If an ecosystem has not defined its own graphing strategy, then we use a best-effort generic one.
      Generic
    end

    sig { params(package_manager: String, grapher: T.class_of(Base)).void }
    def self.register(package_manager, grapher)
      @graphers[package_manager] = grapher
    end
  end
end
