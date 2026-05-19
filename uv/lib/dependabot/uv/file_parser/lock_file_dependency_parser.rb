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

        # uv.lock is the resolved source of truth for installed versions. When a
        # package also appears in a (possibly stale) requirements.txt/.in file,
        # prefer the lockfile version while preserving requirements so the file
        # updater can still operate on those files.
        sig do
          params(dependencies: T::Array[Dependabot::Dependency])
            .returns(T::Array[Dependabot::Dependency])
        end
        def prefer_lockfile_versions(dependencies)
          return dependencies if versions_by_name.empty?

          dependencies.map do |dep|
            lock_version = versions_by_name[dep.name]
            next dep if lock_version.nil? || dep.version == lock_version

            Dependabot::Dependency.new(
              name: dep.name,
              version: lock_version,
              requirements: dep.requirements,
              package_manager: dep.package_manager,
              subdependency_metadata: dep.subdependency_metadata,
              metadata: dep.metadata
            )
          end
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

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
        def versions_by_name
          @versions_by_name ||= T.let(
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
