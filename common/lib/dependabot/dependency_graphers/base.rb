# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module DependencyGraphers
    # This is a small value class that specifies the information we expect to be returned for each
    # dependency strictly.
    class ResolvedDependency < T::ImmutableStruct
      # A valid purl for the dependency, e.g. pkg:/npm/tunnel@0.0.6
      const :package_url, String
      # Is this a direct dependency?
      const :direct, T::Boolean
      # Is this a runtime dependency?
      const :runtime, T::Boolean
      # A list of packages this dependency itself depends on if direct is false. Note that:
      # - a valid purl for the parent dependency is preferable
      # - the package name is acceptable **unless the ecosystem allows multiple versions of a package to be used**
      const :dependencies, T::Array[String]
    end

    class Base
      extend T::Sig
      extend T::Helpers

      PURL_TEMPLATE = "pkg:%<type>s/%<name>s%<version>s"

      abstract!

      sig { returns(T::Boolean) }
      attr_reader :prepared

      sig do
        params(file_parser: Dependabot::FileParsers::Base).void
      end
      def initialize(file_parser:)
        @file_parser = file_parser
        @dependencies = T.let([], T::Array[Dependabot::Dependency])
        @prepared = T.let(false, T::Boolean)
      end

      # Each grapher must implement a heuristic to determine which dependency file should be used as the owner
      # of the resolved_dependencies.
      #
      # Conventionally, this is the lockfile for the file set but some parses may only include the manifest
      # so this method should take into account the correct priority based on which files were parsed.
      sig { abstract.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file; end

      # A grapher may override this method if it needs to perform extra steps around the normal file parser for
      # the ecosystem.
      sig { void }
      def prepare!
        @dependencies = @file_parser.parse
        @prepared = true
      end

      sig { returns(T::Hash[String, ResolvedDependency]) }
      def resolved_dependencies
        prepare! unless prepared

        @dependencies.each_with_object({}) do |dep, resolved|
          resolved[dep.name] = ResolvedDependency.new(
            package_url: build_purl(dep),
            direct: dep.top_level?,
            runtime: dep.production?,
            dependencies: fetch_subdependencies(dep)
          )
        end
      end

      private

      sig { returns(Dependabot::FileParsers::Base) }
      attr_reader :file_parser

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def dependency_files
        file_parser.dependency_files
      end

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
      # specifically include the `v` or allow certain prefixes
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
    end
  end
end
