# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_graphers"
require "dependabot/dependency_graphers/base"

module Dependabot
  module GoModules
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      # Used to capture output from `go mod graph`
      #
      # For the 'parent' dependency, we only want to capture the package name since that's what we match on
      # in `fetch_subdependencies` but for the child we want the full version so we can serialise a PURL.
      #
      # The parent and child are space-separated and we process one line at a time.
      #
      # Example output:
      #   github.com/dependabot/core-test rsc.io/sampler@v1.3.0
      #   rsc.io/sampler@v1.3.0 golang.org/x/text@v0.0.0-20170915032832-14c0d48ead0c
      #   <---parent--->        <----------------------child----------------------->
      #
      GO_MOD_GRAPH_LINE_REGEX = /^(?<parent>[^@\s]+)@?[^\s]*\s(?<child>.*)/

      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        # This cannot realistically happen as the parser will throw a runtime error on init without a go_mod file,
        # but this will avoid surprises if anything changes.
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
        package_relationships.fetch(dependency.name, [])
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def go_mod
        return @go_mod if defined?(@go_mod)

        @go_mod = T.let(
          dependency_files.find { |f| f.name = "go.mod" },
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

      sig { returns(T::Hash[String, T.untyped]) }
      def package_relationships
        @package_relationships ||= T.let(
          fetch_package_relationships,
          T.nilable(T::Hash[String, T.untyped])
        )
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def fetch_package_relationships
        T.cast(
          file_parser,
          Dependabot::GoModules::FileParser
        ).run_in_parsed_context("go mod graph").lines.each_with_object({}) do |line, rels|
          match = line.match(GO_MOD_GRAPH_LINE_REGEX)
          unless match
            Dependabot.logger.warn("Unexpected output from 'go mod graph': 'line'")
            next
          end

          rels[match[:parent]] ||= []
          rels[match[:parent]] << format(
            PURL_TEMPLATE,
            type: "golang",
            name: match[:child],
            version: "" # match[:child] includes the version
          )
        end
      end
    end
  end
end

Dependabot::DependencyGraphers.register("go_modules", Dependabot::GoModules::DependencyGrapher)
