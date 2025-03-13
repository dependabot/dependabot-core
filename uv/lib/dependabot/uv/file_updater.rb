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

      require_relative "file_updater/compile_file_updater"
      require_relative "file_updater/lock_file_updater"
      require_relative "file_updater/requirement_file_updater"

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [
          /^.*\.txt$/,               # Match any .txt files (e.g., requirements.txt) at any level
          /^.*\.in$/,                # Match any .in files at any level
          /^.*pyproject\.toml$/,     # Match pyproject.toml at any level
          /^.*uv\.lock$/             # Match uv.lock at any level
        ]
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def updated_dependency_files
        updated_files = updated_pip_compile_based_files
        updated_files += updated_uv_lock_files

        if updated_files.none? ||
           updated_files.sort_by(&:name) == dependency_files.sort_by(&:name)
          raise "No files have changed!"
        end

        updated_files
      end

      private

      sig { returns(T.nilable(Symbol)) }
      def subdependency_resolver
        raise "Claimed to be a sub-dependency, but no lockfile exists!" if pip_compile_files.empty?

        :pip_compile if pip_compile_files.any?
      end

      sig { returns(T::Array[DependencyFile]) }
      def updated_pip_compile_based_files
        CompileFileUpdater.new(
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

      sig { returns(T::Array[DependencyFile]) }
      def updated_uv_lock_files
        LockFileUpdater.new(
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
        return if pyproject

        raise "Missing required files!"
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pyproject
        @pyproject ||= T.let(get_original_file("pyproject.toml"), T.nilable(Dependabot::DependencyFile))
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
