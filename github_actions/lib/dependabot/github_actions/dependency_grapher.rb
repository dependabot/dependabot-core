# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_graphers"
require "dependabot/dependency_graphers/base"
require "dependabot/github_actions/file_parser"

module Dependabot
  module GithubActions
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      extend T::Sig

      # Every workflow / action file that shares a directory is an independent manifest, so group each file we've found.
      sig { override.returns(T::Array[Dependabot::DependencyGraphers::ManifestGroup]) }
      def manifest_groups
        manifest_files.map do |file|
          Dependabot::DependencyGraphers::ManifestGroup.new(primary: file, files: [file])
        end
      end

      # TODO: Make `relevant_dependency_file` a protected method?
      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        # Satisfies the abstract contract but is not consulted: `manifest_groups` always attributes each
        # file to itself, so we never fall back to the base whole-directory grouping. We return the last
        # manifest file to mirror the generic "right-most file" heuristic if a caller ever reaches this.
        T.must(manifest_files.last)
      end

      private

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def manifest_files
        dependency_files.reject { |file| file.support_file? || file.vendored_file? }
      end

      # GitHub Actions dependencies are flat: an action reference has no resolvable sub-dependencies, so we
      # rely on any `depends_on` metadata the parser may attach (usually none).
      sig { override.params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def fetch_subdependencies(dependency)
        dependency.metadata.fetch(:depends_on, [])
      end

      sig { override.params(_dependency: Dependabot::Dependency).returns(String) }
      def purl_pkg_for(_dependency)
        "github"
      end
    end
  end
end

Dependabot::DependencyGraphers.register("github_actions", Dependabot::GithubActions::DependencyGrapher)
