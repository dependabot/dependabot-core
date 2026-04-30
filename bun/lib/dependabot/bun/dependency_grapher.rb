# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_graphers"
require "dependabot/dependency_graphers/base"
require "dependabot/bun/file_parser"
require "dependabot/bun/bun_package_manager"

module Dependabot
  module Bun
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      extend T::Sig

      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        lockfile || package_json
      end

      private

      sig { override.params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def fetch_subdependencies(dependency)
        []
      end

      sig { override.params(_dependency: Dependabot::Dependency).returns(String) }
      def purl_pkg_for(_dependency)
        "npm"
      end

      sig { override.params(dependency: Dependabot::Dependency).returns(String) }
      def purl_name_for(dependency)
        dependency.name.sub(/^@/, "%40")
      end

      sig { returns(Dependabot::DependencyFile) }
      def package_json
        return T.must(@package_json) if defined?(@package_json)

        T.must(
          @package_json = T.let(
            T.must(dependency_files.find { |f| f.name.end_with?("package.json") }),
            T.nilable(Dependabot::DependencyFile)
          )
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        return @lockfile if defined?(@lockfile)

        @lockfile = T.let(
          dependency_files.find { |f| f.name.end_with?(BunPackageManager::LOCKFILE_NAME) },
          T.nilable(Dependabot::DependencyFile)
        )
      end
    end
  end
end

Dependabot::DependencyGraphers.register("bun", Dependabot::Bun::DependencyGrapher)
