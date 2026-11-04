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
        # Clone the repository temporarily to let Julia helper identify the correct files
        SharedHelpers.in_a_temporary_repo_directory(directory, repo_contents_path) do |temp_dir|
          fetch_files_using_julia_helper(temp_dir)
        end
      end

      private

      sig { params(temp_dir: T.any(Pathname, String)).returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_files_using_julia_helper(temp_dir)
        workspace_info = registry_client.find_workspace_project_files(temp_dir.to_s)
        if workspace_info.is_a?(Dependabot::Julia::RegistryClient::Result::Failure)
          raise_workspace_failure(workspace_info, temp_dir.to_s)
        end

        project_files = workspace_info.project_files
        manifest_paths = workspace_info.manifest_files
        manifest_paths = [workspace_info.manifest_file] if manifest_paths.empty?

        fetched_files = fetch_all_project_files(project_files, temp_dir.to_s)
        raise Dependabot::DependencyFileNotFound, "No Project.toml or JuliaProject.toml found." if fetched_files.empty?

        manifest_paths.each do |manifest_path|
          fetch_manifest_file(fetched_files, manifest_path, project_files, temp_dir.to_s)
        end
        fetched_files
      end

      # Pkg refuses a project it cannot read (a [compat] entry for a package
      # in no dependency section, say), so report its reason against the
      # project file rather than claiming there is none
      sig do
        params(failure: Dependabot::Julia::RegistryClient::Result::Failure, temp_dir: String).returns(T.noreturn)
      end
      def raise_workspace_failure(failure, temp_dir)
        project_name = %w(JuliaProject.toml Project.toml).find { |name| File.exist?(File.join(temp_dir, name)) }
        raise Dependabot::DependencyFileNotFound, "No Project.toml or JuliaProject.toml found." unless project_name

        raise Dependabot::DependencyFileNotParseable.new(
          File.join(directory, project_name),
          relative_to(failure.message, temp_dir)
        )
      end

      # Pkg may report the temporary directory by its realpath
      # ("/private/tmp/..." on macOS); strip that first so the shorter form
      # cannot match inside it
      sig { params(message: String, dir: String).returns(String) }
      def relative_to(message, dir)
        prefixes = [File.exist?(dir) ? File.realpath(dir) : dir, dir].uniq.map { |prefix| File.join(prefix, "") }
        prefixes.reduce(message) { |text, prefix| text.gsub(prefix, "") }
      end

      sig { params(project_files: T::Array[String], base_dir: String).returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_all_project_files(project_files, base_dir)
        project_files.filter_map do |project_path|
          project_relative = Pathname.new(project_path).relative_path_from(Pathname.new(base_dir)).to_s
          fetch_file_if_present(project_relative)
        end
      end

      sig do
        params(
          fetched_files: T::Array[Dependabot::DependencyFile],
          manifest_path: String,
          project_files: T::Array[String],
          base_dir: String
        ).void
      end
      def fetch_manifest_file(fetched_files, manifest_path, project_files, base_dir)
        return if manifest_path.empty? || !File.exist?(manifest_path)

        primary_project_path = project_files.find { |p| File.dirname(p) == base_dir } || project_files.first
        primary_project_dir = File.dirname(T.must(primary_project_path))
        manifest_relative = Pathname.new(manifest_path).relative_path_from(Pathname.new(primary_project_dir)).to_s

        manifest_file = fetch_file_if_present(manifest_relative)
        fetched_files << manifest_file if manifest_file
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
