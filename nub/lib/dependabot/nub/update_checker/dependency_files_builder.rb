# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/nub/file_updater/npmrc_builder"
require "dependabot/nub/file_updater/package_json_preparer"

module Dependabot
  module Nub
    class UpdateChecker
      class DependencyFilesBuilder
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          )
            .void
        end
        def initialize(dependency:, dependency_files:, credentials:)
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
        end

        sig { void }
        def write_temporary_dependency_files
          write_lockfiles

          File.write(".npmrc", npmrc_content)

          package_files.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(file.name, prepared_package_json_content(file))
          end
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def nub_locks
          @nub_locks ||= T.let(
            dependency_files
            .select { |f| f.name.end_with?("nub.lock") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def root_nub_lock
          @root_nub_lock ||= T.let(
            dependency_files
            .find { |f| f.name == "nub.lock" },
            T.nilable(Dependabot::DependencyFile)
          )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def lockfiles
          [*nub_locks]
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def package_files
          @package_files ||= T.let(
            dependency_files
            .select { |f| f.name.end_with?("package.json") },
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { void }
        def write_lockfiles
          nub_locks.each do |f|
            FileUtils.mkdir_p(Pathname.new(f.name).dirname)
            File.write(f.name, f.content)
          end
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def prepared_package_json_content(file)
          Nub::FileUpdater::PackageJsonPreparer.new(
            package_json_content: T.must(file.content)
          ).prepared_content
        end

        sig { returns(String) }
        def npmrc_content
          Nub::FileUpdater::NpmrcBuilder.new(
            credentials: credentials,
            dependency_files: dependency_files
          ).npmrc_content
        end
      end
    end
  end
end
