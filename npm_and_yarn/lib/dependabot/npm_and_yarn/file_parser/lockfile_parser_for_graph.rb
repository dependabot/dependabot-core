# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class LockFileParserForGraph
      extend T::Helpers
      extend T::Sig
      abstract!

      # Builds a dependency graph from the main dependencies and the lockfile
      sig do
        abstract.params(main_dependencies: T::Hash[String, Dependabot::Dependency]).returns(Dependabot::DependencyGraph)
      end
      def build_dependency_graph(main_dependencies); end
    end
  end
end
