# typed: strict
# frozen_string_literal: true

require "toml-rb"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"
require "sorbet-runtime"

module Dependabot
  module Uv
    class FileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig

      require_relative "file_updater/pipfile_file_updater"
      require_relative "file_updater/pip_compile_file_updater"
      require_relative "file_updater/poetry_file_updater"
      require_relative "file_updater/requirement_file_updater"

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [
          /^.*Pipfile$/,             # Match Pipfile at any level
          /^.*Pipfile\.lock$/,       # Match Pipfile.lock at any level
          /^.*\.txt$/,               # Match any .txt files (e.g., requirements.txt) at any level
          /^.*\.in$/,                # Match any .in files at any level
          /^.*setup\.py$/,           # Match setup.py at any level
          /^.*setup\.cfg$/,          # Match setup.cfg at any level
          /^.*pyproject\.toml$/,     # Match pyproject.toml at any level
          /^.*pyproject\.lock$/,     # Match pyproject.lock at any level
          /^.*poetry\.lock$/ # Match poetry.lock at any level
        ]
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def updated_dependency_files
        updated_files = updated_pip_compile_based_files

        if updated_files.none? ||
           updated_files.sort_by(&:name) == dependency_files.sort_by(&:name)
          raise "No files have changed!"
        end

        updated_files
      end

      private

      sig { returns(Symbol) }
      def subdependency_resolver
        return :pipfile if pipfile_lock
        return :poetry if poetry_lock
        return :pip_compile if pip_compile_files.any?

        raise "Claimed to be a sub-dependency, but no lockfile exists!"
      end

      sig { returns(T::Array[DependencyFile]) }
      def updated_pipfile_based_files
        PipfileFileUpdater.new(
          dependencies: dependencies,
          dependency_files: dependency_files,
          credentials: credentials,
          repo_contents_path: repo_contents_path
        ).updated_dependency_files
      end

      sig { returns(T::Array[DependencyFile]) }
      def updated_poetry_based_files
        PoetryFileUpdater.new(
          dependencies: dependencies,
          dependency_files: dependency_files,
          credentials: credentials
        ).updated_dependency_files
      end

      sig { returns(T::Array[DependencyFile]) }
      def updated_pip_compile_based_files
        PipCompileFileUpdater.new(
          dependencies: dependencies,
          dependency_files: dependency_files,
          credentials: credentials,
          index_urls: pip_compile_index_urls
        ).updated_dependency_files
      end

      sig { returns(T::Array[DependencyFile]) }
      def updated_requirement_based_files
        RequirementFileUpdater.new(
          dependencies: dependencies,
          dependency_files: dependency_files,
          credentials: credentials,
          index_urls: pip_compile_index_urls
        ).updated_dependency_files
      end

      sig { returns(T::Array[String]) }
      def pip_compile_index_urls
        if credentials.any?(&:replaces_base?)
          credentials.select(&:replaces_base?).map { |cred| AuthedUrlBuilder.authed_url(credential: cred) }
        else
          urls = credentials.map { |cred| AuthedUrlBuilder.authed_url(credential: cred) }
          # If there are no credentials that replace the base, we need to
          # ensure that the base URL is included in the list of extra-index-urls.
          [nil, *urls]
        end
      end

      sig { override.void }
      def check_required_files
        filenames = dependency_files.map(&:name)
        return if filenames.any? { |name| name.end_with?(".txt", ".in") }
        return if pipfile
        return if pyproject
        return if get_original_file("setup.py")
        return if get_original_file("setup.cfg")

        raise "Missing required files!"
      end

      sig { returns(T::Boolean) }
      def poetry_based?
        return false unless pyproject

        !TomlRB.parse(pyproject&.content).dig("tool", "poetry").nil?
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pipfile
        @pipfile ||= T.let(get_original_file("Pipfile"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pipfile_lock
        @pipfile_lock ||= T.let(get_original_file("Pipfile.lock"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pyproject
        @pyproject ||= T.let(get_original_file("pyproject.toml"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def poetry_lock
        @poetry_lock ||= T.let(get_original_file("poetry.lock"), T.nilable(Dependabot::DependencyFile))
      end

      sig { returns(T::Array[DependencyFile]) }
      def pip_compile_files
        @pip_compile_files ||= T.let(
          dependency_files.select { |f| f.name.end_with?(".in") },
          T.nilable(T::Array[DependencyFile])
        )
      end
    end
  end
end

Dependabot::FileUpdaters.register("uv", Dependabot::Uv::FileUpdater)
