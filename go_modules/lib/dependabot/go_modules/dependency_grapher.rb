# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_graphers"
require "dependabot/dependency_graphers/base"

module Dependabot
  module GoModules
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        raise DependabotError, "No go.mod present in dependency files." unless go_mod

        T.must(go_mod)
      end

      private

      # TODO: Build subdependency in this class and assign here -or- assign metadata in the parser
      #
      # We can do whichever makes most sense on a case-by-case basis, for Go the trade off on
      # doing this in the parser shouldn't add a huge overhead.
      sig { override.params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def fetch_subdependencies(dependency)
        dependency.metadata.fetch(:depends_on, [])
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_mod
        return @go_mod if defined?(@go_mod)

        @go_mod = T.let(
          @dependency_files.find { |f| f.name = "go.mod" },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      # In Go, the `v` is considered a canonical part of the version and omitting it can make
      # comparisons tricky
      sig { params(dependency: Dependabot::Dependency).returns(String) }
      def purl_version_for(dependency)
        return "" unless dependency.version

        "@v#{dependency.version}"
      end

      sig { override.params(_dependency: Dependabot::Dependency).returns(String) }
      def purl_pkg_for(_dependency)
        "golang"
      end
    end
  end
end

Dependabot::DependencyGraphers.register("go_modules", Dependabot::GoModules::DependencyGrapher)
