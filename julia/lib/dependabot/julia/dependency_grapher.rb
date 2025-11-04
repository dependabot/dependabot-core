# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_graphers"
require "dependabot/dependency_graphers/base"

# NOTE: This is a quick proof-of-concept
#
# This is a very basic spike into graphing Julia written without much deep understanding of the ecosystem.
#
# There are several notes below on
module Dependabot
  module Julia
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        # TODO: Use dependency versions from manifests, Handle versioned manifests
        #
        # See notes on methods below:
        # - purl_version_for for dependency versions
        # - manifest_file for versioned manifests
        # return manifest_file if manifest_file
        return project_file if project_file

        raise DependabotError, "No Project.toml or Manifest.toml to specify dependencies for."
      end

      private

      sig { override.params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def fetch_subdependencies(dependency)
        [] # For now, we do not attempt to build dependency relationships.
      end

      sig { override.params(_dependency: Dependabot::Dependency).returns(String) }
      def purl_pkg_for(_dependency)
        "generic"
      end

      # This currently won't handle versioned manifests, e.g. Manifest-v1.12.toml
      #
      # I suspect the correct answer is to use the Manifest that matches the Julia version
      # Dependabot is utilising, if available, and otherwise expect an unversioned manifest.
      #
      # I'm not sure it would be practical to expansively parse multiple manifests, given we
      # only reporting on requirements and not locked versions we can ignore this for now.
      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def manifest_file
        return @manifest_file if defined?(@manifest_file)

        @manifest_file = T.let(
          dependency_files.find { |f| f.name == "Manifest.toml" },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def project_file
        return @project_file if defined?(@project_file)

        @project_file = T.let(
          dependency_files.find { |f| f.name == "Project.toml" },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      # FIXME: This returns declared versions, not resolved versions
      #
      # This behaviour is semantically incorrect, we do not set dependency.version when parsing files even if
      # a Manifest.toml is available with a resolved version.
      #
      # Strictly, this means we should return all dependencies in the form:
      # - pkg:generic/Foo
      #
      # This may be good enough, but from a dependency composition analysis perspective it means we will end up making
      # assumptions for vulnerability detection (match all vulns?) and SBOMs (use the latest license?).
      #
      # I think we should look at setting dependency.version if a Manifest.toml is available during parsing
      # an alternative could be to expand the dependencies returned to the list of compatible versions, i.e.
      #
      # We would always report Project.toml as the relevant dependency file and return three PURLs as possible
      # versions in use:
      # - pkg:generic/Foo@0.7
      # - pkg:generic/Foo@0.8
      # - pkg:generic/Foo@0.9
      #
      # This optimises for expansive graphing of the possible versions in use across all builds at the expense
      # of over-reporting on three versions.
      sig { params(dependency: Dependabot::Dependency).returns(String) }
      def purl_version_for(dependency)
        requirement = dependency.requirements.first&.fetch(:requirement, "")
        return requirement unless requirement != ""

        "@#{requirement}"
      end
    end
  end
end

Dependabot::DependencyGraphers.register("julia", Dependabot::Julia::DependencyGrapher)
