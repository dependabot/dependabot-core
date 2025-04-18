# typed: strong
# frozen_string_literal: true

require "dependabot/update_checkers/base"
require "dependabot/swift/file_parser/dependency_parser"
require "dependabot/swift/file_updater/lockfile_updater"
require "sorbet-runtime"

module Dependabot
  module Swift
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class VersionResolver
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            manifest: Dependabot::DependencyFile,
            lockfile: T.nilable(Dependabot::DependencyFile),
            repo_contents_path: T.nilable(String),
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependency:, manifest:, lockfile:, repo_contents_path:, credentials:)
          @dependency         = dependency
          @manifest           = manifest
          @lockfile           = lockfile
          @credentials        = credentials
          @repo_contents_path = repo_contents_path
        end

        sig { returns(T.nilable(String)) }
        def latest_resolvable_version
          @latest_resolvable_version ||= T.let(
            fetch_latest_resolvable_version,
            T.nilable(String)
          )
        end

        private

        sig { returns(T.nilable(String)) }
        def fetch_latest_resolvable_version
          updated_lockfile_content = FileUpdater::LockfileUpdater.new(
            dependency: dependency,
            manifest: manifest,
            repo_contents_path: T.must(repo_contents_path),
            credentials: credentials
          ).updated_lockfile_content

          return if lockfile && updated_lockfile_content == T.must(lockfile).content

          updated_lockfile = DependencyFile.new(
            name: "Package.resolved",
            content: updated_lockfile_content,
            directory: manifest.directory
          )

          dependency_parser(manifest, updated_lockfile).parse.find do |parsed_dep|
            parsed_dep.name == dependency.name
          end&.version
        end

        sig do
          params(
            manifest: Dependabot::DependencyFile,
            lockfile: Dependabot::DependencyFile
          )
            .returns(FileParser::DependencyParser)
        end
        def dependency_parser(manifest, lockfile)
          FileParser::DependencyParser.new(
            dependency_files: [manifest, lockfile].compact,
            repo_contents_path: repo_contents_path,
            credentials: credentials
          )
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :manifest

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        attr_reader :lockfile

        sig { returns(T.nilable(String)) }
        attr_reader :repo_contents_path

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials
      end
    end
  end
end
