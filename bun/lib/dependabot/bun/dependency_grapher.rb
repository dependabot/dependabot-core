# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_graphers"
require "dependabot/dependency_graphers/base"
require "dependabot/bun/file_parser"
require "dependabot/bun/file_parser/bun_lock"
require "dependabot/bun/bun_package_manager"

module Dependabot
  module Bun
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      extend T::Sig

      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        lockfile || package_json
      end

      sig { override.void }
      def prepare!
        if lockfile.nil?
          Dependabot.logger.warn("No bun.lock found; dependency graph will be incomplete.")
          errored_fetching_subdependencies!
        end
        super
      end

      private

      sig { override.params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def fetch_subdependencies(dependency)
        package_relationships.fetch(dependency.name, [])
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

      sig { returns(T::Hash[String, T::Array[String]]) }
      def package_relationships
        @package_relationships ||= T.let(
          fetch_package_relationships,
          T.nilable(T::Hash[String, T::Array[String]])
        )
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def fetch_package_relationships
        return {} unless lockfile

        parsed_lockfile = FileParser::BunLock.new(T.must(lockfile)).parsed
        packages = parsed_lockfile.fetch("packages", nil)
        return {} unless packages.is_a?(Hash)

        # bun.lock entries are arrays: ["{name}@{version}", registry, {details}, integrity]
        packages.each_with_object({}) do |(_key, entry), rels|
          next unless entry.is_a?(Array) && entry.first.is_a?(String)

          parent_name = T.must(T.cast(entry.first, String).split(/(?<=\w)\@/).first)
          children = entry.dig(2, "dependencies")&.keys
          next unless children&.any?

          rels[parent_name] = children
        end
      end
    end
  end
end

Dependabot::DependencyGraphers.register("bun", Dependabot::Bun::DependencyGrapher)
