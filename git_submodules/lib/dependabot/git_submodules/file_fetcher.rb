# typed: strict
# frozen_string_literal: true

require "parseconfig"
require "sorbet-runtime"
require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/shared_helpers"

module Dependabot
  module GitSubmodules
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.include?(".gitmodules")
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a .gitmodules file."
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = []
        fetched_files << gitmodules_file
        fetched_files += submodule_refs
        fetched_files
      end

      private

      sig { returns(Dependabot::DependencyFile) }
      def gitmodules_file
        @gitmodules_file ||=
          T.let(
            fetch_file_from_host(".gitmodules"),
            T.nilable(Dependabot::DependencyFile)
          )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def submodule_refs
        @submodule_refs ||=
          T.let(
            submodule_paths
            .map { |path| fetch_submodule_ref_from_host(path) }
            .tap { |refs| refs.each { |f| f.support_file = false } }
            .uniq,
            T.nilable(T::Array[Dependabot::DependencyFile])
          )
      end

      sig { returns(T::Array[String]) }
      def submodule_paths
        @submodule_paths ||=
          T.let(
            Dependabot::SharedHelpers.in_a_temporary_directory do
              File.write(".gitmodules", gitmodules_file.content)
              ParseConfig.new(".gitmodules").params.values.map { |p| p["path"] }
            end,
            T.nilable(T::Array[String])
          )
      end

      sig { params(submodule_path: T.nilable(String)).returns(Dependabot::DependencyFile) }
      def fetch_submodule_ref_from_host(submodule_path)
        path = Pathname.new(File.join(directory, submodule_path))
                       .cleanpath.to_path.gsub(%r{^/*}, "")
        sha =  case source.provider
               when "github"
                 fetch_github_submodule_commit(path)
               when "gitlab"
                 tmp_path = path.gsub(%r{^/*}, "")
                 T.unsafe(gitlab_client).get_file(repo, tmp_path, commit).blob_id
               when "azure"
                 azure_client.fetch_file_contents(T.must(commit), path)
               else raise "Unsupported provider '#{source.provider}'."
               end

        DependencyFile.new(
          name: Pathname.new(submodule_path).cleanpath.to_path,
          content: sha,
          directory: directory,
          type: "submodule"
        )
      rescue Octokit::NotFound,
             Gitlab::Error::NotFound,
             Dependabot::Clients::Azure::NotFound
        raise Dependabot::DependencyFileNotFound, path
      end

      sig { params(path: String).returns(String) }
      def fetch_github_submodule_commit(path)
        content = T.unsafe(github_client).contents(
          repo,
          path: path,
          ref: commit
        )
        raise Dependabot::DependencyFileNotFound, path if content.is_a?(Array) || content.type != "submodule"

        content.sha
      end
    end
  end
end

Dependabot::FileFetchers
  .register("submodules", Dependabot::GitSubmodules::FileFetcher)
