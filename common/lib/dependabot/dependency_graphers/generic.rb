# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_graphers/base"

module Dependabot
  module DependencyGraphers
    class Generic < Base
      extend T::Sig
      extend T::Helpers

      # Our generic strategy is to use the right-most file in the dependency file list on the
      # assumption that this is normally the lockfile.
      #
      # This isn't a durable strategy but it's good enough to allow most ecosystems to 'just work'
      # as we roll out ecosystem-specific graphers.
      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        files = filtered_dependency_files
        T.must(files.last)
      end

      private

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def filtered_dependency_files
        dependency_files.reject { |f| f.support_file? || f.vendored_file? }
      end

      # Generic strategy: convert metadata :depends_on (names) into Dependency objects
      sig { override.params(dependency: Dependabot::Dependency).returns(T::Array[Dependabot::Dependency]) }
      def fetch_subdependencies(dependency, all_dependencies)
        names = dependency.metadata.fetch(:depends_on, [])
        return [] if names.empty?

        names.each_with_object([]) do |name, arr|
          dep_obj = all_dependencies.find { |d| d.name == name }
          arr << dep_obj if dep_obj
        end
      end

      # TODO: Delegate this to ecosystem-specific base classes
      sig { override.params(dependency: Dependabot::Dependency).returns(String) }
      def purl_pkg_for(dependency)
        case dependency.package_manager
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
    end
  end
end
