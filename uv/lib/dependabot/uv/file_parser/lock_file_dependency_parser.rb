# typed: strict
# frozen_string_literal: true

require "toml-rb"

require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/uv/file_parser"
require "dependabot/uv/name_normaliser"

module Dependabot
  module Uv
    class FileParser
      # Parses dependencies out of uv.lock files and provides a helper for
      # preferring lockfile-resolved versions over any (potentially stale)
      # versions discovered in requirements.txt/.in or pyproject.toml.
      class LockFileDependencyParser
        extend T::Sig

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependency_set
          @dependency_set ||= T.let(
            build_dependency_set,
            T.nilable(Dependabot::FileParsers::Base::DependencySet)
          )
        end

        # `DependencySet#combined_version` can pick a stale `requirements.txt`
        # version over `uv.lock` when both list the same package — `uv.lock`
        # entries have empty requirements (so `top_level?` is false) and lose
        # the merge. Override the merged version with the lockfile version for
        # any package present in `uv.lock`, keeping the merged requirements so
        # the file updater can still operate on the requirements files.
        sig do
          params(dependencies: T::Array[Dependabot::Dependency])
            .returns(T::Array[Dependabot::Dependency])
        end
        def override_with_lockfile_versions(dependencies)
          return dependencies if lockfile_versions.empty?

          dependencies.map { |dep| override_version(dep, lockfile_versions[dep.name]) }
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig do
          params(dep: Dependabot::Dependency, lock_version: T.nilable(String))
            .returns(Dependabot::Dependency)
        end
        def override_version(dep, lock_version)
          return dep if lock_version.nil? # not in uv.lock
          return dep if dep.version == lock_version # merged version already correct

          Dependabot::Dependency.new(
            name: dep.name,
            version: lock_version,
            requirements: dep.requirements,
            package_manager: dep.package_manager,
            subdependency_metadata: dep.subdependency_metadata,
            metadata: dep.metadata
          )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def uv_lock_files
          dependency_files.select { |f| f.name == "uv.lock" }
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def build_dependency_set
          set = Dependabot::FileParsers::Base::DependencySet.new

          uv_lock_files.each do |file|
            lockfile_content = TomlRB.parse(file.content)
            packages = lockfile_content.fetch("package", [])

            packages.each do |package_data|
              next unless package_data.is_a?(Hash) && package_data["name"] && package_data["version"]

              set << Dependabot::Dependency.new(
                name: NameNormaliser.normalise(package_data["name"]),
                version: package_data["version"],
                requirements: [], # Lock files don't contain requirements
                package_manager: "uv"
              )
            end
          rescue StandardError => e
            Dependabot.logger.warn("Error parsing uv.lock: #{e.message}")
          end

          set
        end

        sig { returns(T::Hash[String, String]) }
        def lockfile_versions
          @lockfile_versions ||= T.let(
            dependency_set.dependencies.each_with_object({}) do |dep, hash|
              version = dep.version
              hash[dep.name] = version if version
            end,
            T.nilable(T::Hash[String, String])
          )
        end
      end
    end
  end
end
