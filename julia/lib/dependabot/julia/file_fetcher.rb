# typed: strong
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/julia/shared"

module Dependabot
  module Julia
    class FileFetcher < Dependabot::FileFetchers::Base
      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? do |name|
          Shared::PROJECT_NAMES.any? { |project_name| name.match?(project_name) }
        end
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a Project.toml file."
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_files
        fetched_files = []

        # Get the main project file
        project_file = find_project_file

        # Get the manifest file (may be versioned)
        manifest_file = find_manifest_file

        fetched_files << project_file if project_file
        fetched_files << manifest_file if manifest_file

        # Load additional files
        fetched_files
      end

      private

      # Method needed for testing
      sig { params(filename: String).returns(String) }
      def fetch_file_content(filename)
        file = fetch_file_from_host(File.join(directory, filename))
        T.must(file.content)
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def find_project_file
        project_files = fetch_files_with_name(T.must(Shared::PROJECT_NAMES.first))
        raise "Multiple project files found!" if project_files.count > 1

        project_files.first
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def find_manifest_file
        # Try to determine Julia version to find correct manifest name
        version = nil
        begin
          version = T.must(SharedHelpers.run_shell_command("julia --version")
                              .match(/(\d+\.\d+)/))[1]
        rescue StandardError => e
          Dependabot.logger.error("Error detecting Julia version: #{e}")
        end

        # Try versioned manifest names based on Julia version
        Shared.manifest_names(T.must(version)).each do |name|
          manifest_files = fetch_files_with_name(name)
          return manifest_files.first if manifest_files.any?
        end

        # Fall back to generic manifest name
        fetch_files_with_name("Manifest.toml").first
      end

      sig { params(filename: String).returns(T::Array[DependencyFile]) }
      def fetch_files_with_name(filename)
        files = []

        # Use FileFetchers::Base methods to fetch files
        path = File.join(directory, filename)
        file = fetch_file_from_host(path)
        files << file if file

        files
      rescue Dependabot::DependencyFileNotFound
        []
      end
    end
  end
end

Dependabot::FileFetchers.register("julia", Dependabot::Julia::FileFetcher)
