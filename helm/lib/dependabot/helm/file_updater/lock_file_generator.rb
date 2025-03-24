# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/shared_helpers"
require "fileutils"
require "tmpdir"

module Dependabot
  module Helm
    class FileUpdater < Dependabot::Shared::SharedFileUpdater
      class LockFileGenerator
        extend T::Sig

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            dependency_files: T::Array[Dependabot::DependencyFile],
            repo_contents_path: String,
            credentials: T::Array[Dependabot::Credential]
          ).void
        end
        def initialize(dependencies:, dependency_files:, repo_contents_path:, credentials:)
          @dependencies = dependencies
          @dependency_files = dependency_files
          @repo_contents_path = repo_contents_path
          @credentials = credentials
        end

        sig { params(chart_lock: Dependabot::DependencyFile, updated_content: String).returns(String) }
        def updated_chart_lock(chart_lock, updated_content)
          SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
            SharedHelpers.with_git_configured(credentials: credentials) do
              File.write("Chart.yaml", updated_content)
              Helpers.update_lock

              File.read(chart_lock.name)
            end
          end
        end

        private

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies
        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files
        sig { returns(String) }
        attr_reader :repo_contents_path
        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(String) }
        def base_dir
          T.must(dependency_files.first).directory
        end
      end
    end
  end
end
