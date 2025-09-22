# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module DependencyGraphers
    class Base
      extend T::Sig
      extend T::Helpers

      PURL_TEMPLATE = "pkg:%<type>s/%<name>s%<version>s"

      abstract!

      # TODO(brrygrdn): Inject the Dependency parser instead of pre-parsed `dependencies`
      #
      # Semantically it makes sense for the grapher to wrap the parser as a higher order function, but we already know
      # that some package managers will require extra native commands before, after or during the parse - in extreme
      # cases it may make sense to use an alternative parser that is more optimal.
      #
      # By injecting the parser, this allows the ecosystem to encapsulate the package manager specifics without the
      # executor needing to manage parser modes / feature flags.
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
            dependencies: fetch_subdependencies(dep),
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
      def fetch_subdependencies(dependency); end

      # Each grapher is expected to implement a method to map the various package managers it supports to
      # the correct Package-URL type, see:
      #   https://github.com/package-url/purl-spec/blob/main/PURL-TYPES.rst
      sig { abstract.params(dependency: Dependabot::Dependency).returns(String) }
      def purl_pkg_for(dependency); end

      # Our basic strategy is just to use the dependency name, but specific graphers may need to override this
      # to meet formal specifics
      sig { params(dependency: Dependabot::Dependency).returns(String) }
      def purl_name_for(dependency)
        dependency.name
      end

      # We should ensure we don't include an `@` if there isn't a resolved version, but some ecosystems
      # specifically include the version or allow certain prefixes
      sig { params(dependency: Dependabot::Dependency).returns(String) }
      def purl_version_for(dependency)
        return "" unless dependency.version

        "@#{dependency.version}"
      end

      # Generate a purl for the provided Dependency object
      sig { params(dependency: Dependabot::Dependency).returns(String) }
      def build_purl(dependency)
        format(
          PURL_TEMPLATE,
          type: purl_pkg_for(dependency),
          name: purl_name_for(dependency),
          version: purl_version_for(dependency)
        )
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
  end
end
