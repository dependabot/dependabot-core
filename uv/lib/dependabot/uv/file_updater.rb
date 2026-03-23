# typed: strong
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

      require_relative "file_updater/lock_file_updater"
      require_relative "file_updater/requirement_file_updater"

      sig { override.returns(T::Array[DependencyFile]) }
      def updated_dependency_files
        updated_files = updated_requirement_based_files
        updated_files += updated_uv_lock_files
        # Deduplicate in case both updaters return the same file (e.g. pyproject.toml).
        # RequirementFileUpdater results take precedence as they appear first.
        updated_files = updated_files.uniq(&:name)

        if updated_files.none? ||
           updated_files.sort_by(&:name) == dependency_files.sort_by(&:name)
          raise "No files have changed!"
        end

        updated_files
      end

      private

      sig { returns(T::Array[DependencyFile]) }
      def updated_requirement_based_files
        RequirementFileUpdater.new(
          dependencies: dependencies,
          dependency_files: dependency_files,
          credentials: credentials,
          index_urls: index_urls
        ).updated_dependency_files
      end

      sig { returns(T::Array[DependencyFile]) }
      def updated_uv_lock_files
        LockFileUpdater.new(
          dependencies: dependencies,
          dependency_files: dependency_files,
          credentials: credentials,
          index_urls: index_urls,
          repo_contents_path: repo_contents_path
        ).updated_dependency_files
      end

      sig { returns(T::Array[T.nilable(String)]) }
      def index_urls
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
        return if filenames.any? { |name| name.end_with?(".txt") }
        return if pyproject

        raise "Missing required files!"
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pyproject
        @pyproject ||= T.let(get_original_file("pyproject.toml"), T.nilable(Dependabot::DependencyFile))
      end
    end
  end
end

Dependabot::FileUpdaters.register("uv", Dependabot::Uv::FileUpdater)
