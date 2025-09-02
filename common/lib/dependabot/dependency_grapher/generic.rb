# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_grapher/base"

module Dependabot
  module DependencyGrapher
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
        T.must(filtered_dependency_files.last)
      end

      private

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def filtered_dependency_files
        @dependency_files.reject { |f| f.support_file? || f.vendored_file? }
      end

      # Our generic strategy is to check if the parser has attached a `depends_on` key to the Dependency's
      # metadata, but in most cases this will be empty.
      sig { override.params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def fetch_subdependencies(dependency)
        dependency.metadata.fetch(:depends_on, [])
      end

      # TODO: Delegate this to ecosystem-specific base classes
      sig { override.params(package_manager: String).returns(String) }
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
    end
  end
end
