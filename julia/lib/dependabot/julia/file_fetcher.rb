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
        workspace_info = registry_client.detect_workspace_files(temp_dir.to_s)
        validate_workspace_info(workspace_info)

        base_dir = temp_dir.to_s
        project_files = T.cast(workspace_info["project_files"], T::Array[String])
        manifest_path = T.cast(workspace_info["manifest_file"], T.nilable(String))
        is_workspace = T.cast(workspace_info["is_workspace"], T::Boolean)

        manifest_metadata = build_manifest_metadata(manifest_path, base_dir)
        lockfile_path = T.cast(manifest_metadata[:lockfile_path], T.nilable(String))

        fetched_files = fetch_project_files(project_files, base_dir, lockfile_path)
        fetched_files += fetch_manifest_file(manifest_path, manifest_metadata, is_workspace, fetched_files)

        fetched_files
      end

      sig { params(workspace_info: T::Hash[String, T.untyped]).void }
      def validate_workspace_info(workspace_info)
        return unless workspace_info.empty? || T.cast(workspace_info["project_files"], T.nilable(T::Array[String])).nil?

        raise Dependabot::DependencyFileNotFound, "No Project.toml or JuliaProject.toml found."
      end

      sig do
        params(
          manifest_path: T.nilable(String),
          base_dir: String
        ).returns(T::Hash[Symbol, T.nilable(T.any(String, T::Array[String]))])
      end
      def build_manifest_metadata(manifest_path, base_dir)
        if manifest_path.nil? || manifest_path.empty?
          return { manifest_paths: [], lockfile_path: nil, directory: nil,
                   filename: nil }
        end

        relative_path = Pathname.new(manifest_path).relative_path_from(Pathname.new(base_dir)).to_s
        manifest_dir = calculate_repository_directory(File.dirname(relative_path))
        filename = File.basename(manifest_path)

        {
          manifest_paths: T.let([], T::Array[String]),
          lockfile_path: File.join(manifest_dir, filename),
          directory: manifest_dir,
          filename: filename
        }
      end

      sig { params(relative_directory: String).returns(String) }
      def calculate_repository_directory(relative_directory)
        if relative_directory == "."
          directory
        else
          Pathname.new(File.join(directory, relative_directory)).cleanpath.to_s
        end
      end

      sig do
        params(
          project_files: T::Array[String],
          base_dir: String,
          lockfile_path: T.nilable(String)
        ).returns(T::Array[Dependabot::DependencyFile])
      end
      def fetch_project_files(project_files, base_dir, lockfile_path)
        files = T.let([], T::Array[Dependabot::DependencyFile])

        project_files.each do |project_path|
          relative_path = Pathname.new(project_path).relative_path_from(Pathname.new(base_dir)).to_s
          file_directory = calculate_repository_directory(File.dirname(relative_path))

          files << Dependabot::DependencyFile.new(
            name: File.basename(project_path),
            directory: file_directory,
            type: "file",
            content: File.read(project_path),
            associated_lockfile_path: lockfile_path
          )
        end

        files
      end

      sig do
        params(
          manifest_path: T.nilable(String),
          metadata: T::Hash[Symbol, T.nilable(T.any(String, T::Array[String]))],
          is_workspace: T::Boolean,
          fetched_files: T::Array[Dependabot::DependencyFile]
        ).returns(T::Array[Dependabot::DependencyFile])
      end
      def fetch_manifest_file(manifest_path, metadata, is_workspace, fetched_files)
        return [] if manifest_path.nil? || manifest_path.empty?

        manifest_dir = T.cast(metadata[:directory], T.nilable(String))
        manifest_filename = T.cast(metadata[:filename], T.nilable(String))

        return [] unless manifest_dir && manifest_filename
        return [] if already_fetched?(fetched_files, manifest_filename, manifest_dir)
        return [] unless File.exist?(manifest_path)

        manifest_paths = is_workspace ? fetched_files.select { |f| f.name =~ /^(Julia)?Project\.toml$/i }.map { |f| File.join(f.directory, f.name) } : nil

        Dependabot.logger.info("FileFetcher: Creating manifest file with is_workspace=#{is_workspace}, associated_manifest_paths=#{manifest_paths.inspect}")

        [Dependabot::DependencyFile.new(
          name: manifest_filename,
          directory: manifest_dir,
          type: "file",
          content: File.read(manifest_path),
          associated_manifest_paths: manifest_paths
        )]
      end

      sig do
        params(
          files: T::Array[Dependabot::DependencyFile],
          filename: String,
          file_directory: String
        ).returns(T::Boolean)
      end
      def already_fetched?(files, filename, file_directory)
        files.any? { |f| f.name == filename && f.directory == file_directory }
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
