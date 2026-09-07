# typed: strict
# frozen_string_literal: true

require "yaml"
require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/ecosystem"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/codeql/package_manager"

module Dependabot
  module Codeql
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      require "dependabot/file_parsers/base/dependency_set"

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        manifest = load_yaml(qlpack_content)
        lock_data = load_yaml(lockfile_content)
        lock_dependencies = dependencies_from(lock_data)

        dependencies = dependencies_from(manifest).filter_map do |name, requirement|
          build_dependency(name: name, requirement: requirement, lock_dependencies: lock_dependencies)
        end

        dependencies.sort_by(&:name)
      end

      sig { override.returns(Dependabot::Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: "codeql",
            package_manager: package_manager
          ),
          T.nilable(Dependabot::Ecosystem)
        )
      end

      private

      sig { returns(Dependabot::Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(PackageManager.new, T.nilable(Dependabot::Ecosystem::VersionManager))
      end

      sig { params(content: T.nilable(String)).returns(T::Hash[String, Object]) }
      def load_yaml(content)
        data = YAML.safe_load(content || "{}", permitted_classes: [Symbol], aliases: true) || {}
        return {} unless data.is_a?(Hash)

        data.each_with_object({}) do |(key, value), hash|
          hash[key.to_s] = value
        end
      end

      sig { params(data: T::Hash[String, Object]).returns(T::Hash[String, Object]) }
      def dependencies_from(data)
        dependencies = data["dependencies"]
        return {} unless dependencies.is_a?(Hash)

        dependencies.each_with_object({}) do |(name, requirement), hash|
          hash[name.to_s] = requirement
        end
      end

      sig do
        params(name: String, requirement: Object, lock_dependencies: T::Hash[String, Object])
          .returns(T.nilable(Dependabot::Dependency))
      end
      def build_dependency(name:, requirement:, lock_dependencies:)
        return if requirement == "${workspace}"
        return if requirement == "*" && !lock_dependencies.key?(name)

        locked_version = locked_version(lock_dependencies[name])

        Dependency.new(
          name: name,
          version: locked_version.is_a?(String) ? locked_version : nil,
          package_manager: "codeql",
          requirements: [{
            requirement: requirement,
            groups: [],
            file: "qlpack.yml",
            source: { type: "codeql_pack_registry" }
          }]
        )
      end

      sig { params(dependency: T.nilable(Object)).returns(T.nilable(String)) }
      def locked_version(dependency)
        return unless dependency.is_a?(Hash)

        version = dependency["version"]
        version if version.is_a?(String)
      end

      sig { returns(T.nilable(String)) }
      def qlpack_content
        @qlpack_content ||= T.let(get_original_file("qlpack.yml")&.content, T.nilable(String))
      end

      sig { returns(T.nilable(String)) }
      def lockfile_content
        @lockfile_content ||= T.let(get_original_file("codeql-pack.lock.yml")&.content, T.nilable(String))
      end

      sig { override.void }
      def check_required_files
        raise "No qlpack.yml file!" unless get_original_file("qlpack.yml")
      end
    end
  end
end

Dependabot::FileParsers.register("codeql", Dependabot::Codeql::FileParser)
