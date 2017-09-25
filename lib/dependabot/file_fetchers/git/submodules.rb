# frozen_string_literal: true
require "parseconfig"
require "dependabot/file_fetchers/base"
require "dependabot/shared_helpers"

module Dependabot
  module FileFetchers
    module Git
      class Submodules < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          filenames.include?(".gitmodules")
        end

        def self.required_files_message
          "Repo must contain a .gitmodules file."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << gitmodules_file
          fetched_files += submodule_refs
          fetched_files
        end

        def gitmodules_file
          @gitmodules_file ||= fetch_file_from_github(".gitmodules")
        end

        def submodule_refs
          submodule_paths.map { |path| fetch_submodule_ref_from_github(path) }
        end

        def submodule_paths
          SharedHelpers.in_a_temporary_directory do
            File.write(".gitmodules", gitmodules_file.content)
            ParseConfig.new(".gitmodules").params.values.map { |p| p["path"] }
          end
        end

        def fetch_submodule_ref_from_github(submodule_path)
          path = Pathname.new(File.join(directory, submodule_path)).
                 cleanpath.to_path
          sha = github_client.contents(repo, path: path, ref: commit).sha

          DependencyFile.new(
            name: Pathname.new(submodule_path).cleanpath.to_path,
            content: sha,
            directory: directory,
            type: "submodule"
          )
        rescue Octokit::NotFound
          raise Dependabot::DependencyFileNotFound, path
        end
      end
    end
  end
end
