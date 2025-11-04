# typed: strong
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/julia/registry_client"
require "dependabot/shared_helpers"
require "pathname"

module Dependabot
  module Julia
    class FileFetcher < Dependabot::FileFetchers::Base
      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |name| name.match?(/^(Julia)?Project\.toml$/i) }
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a Project.toml or JuliaProject.toml file."
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_files
        # Julia is currently in beta - only fetch files if beta ecosystems are enabled
        return [] unless allow_beta_ecosystems?

        # Clone the repository temporarily to let Julia helper identify the correct files
        SharedHelpers.in_a_temporary_repo_directory(directory, repo_contents_path) do |temp_dir|
          fetch_files_using_julia_helper(temp_dir)
        end
      end

      private

      sig { params(temp_dir: T.any(Pathname, String)).returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_files_using_julia_helper(temp_dir)
        # Use Julia helper to identify the correct environment files
        env_files = registry_client.find_environment_files(temp_dir.to_s)

        if env_files.empty? || !env_files["project_file"]
          raise Dependabot::DependencyFileNotFound, "No Project.toml or JuliaProject.toml found."
        end

        fetched_files = []

        # Fetch the project file identified by Julia helper
        project_path = T.must(env_files["project_file"])
        project_filename = File.basename(project_path)
        fetched_files << fetch_file_from_host(project_filename)

        # Fetch the manifest file if Julia helper found one
        manifest_path = env_files["manifest_file"]
        if manifest_path && !manifest_path.empty?
          # Calculate relative path from project to manifest
          project_dir = File.dirname(project_path)
          manifest_relative = Pathname.new(manifest_path).relative_path_from(Pathname.new(project_dir)).to_s

          # Fetch manifest (handles workspace cases where manifest is in parent directory)
          manifest_file = fetch_file_if_present(manifest_relative)
          fetched_files << manifest_file if manifest_file
        end

        fetched_files
      end

      sig { returns(Dependabot::Julia::RegistryClient) }
      def registry_client
        @registry_client ||= T.let(
          Dependabot::Julia::RegistryClient.new(credentials: credentials),
          T.nilable(Dependabot::Julia::RegistryClient)
        )
      end
    end
  end
end

Dependabot::FileFetchers.register("julia", Dependabot::Julia::FileFetcher)
