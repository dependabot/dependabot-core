# typed: strong
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

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

        fetched_files = []

        # Fetch the main project file (Project.toml or JuliaProject.toml)
        fetched_files << project_file

        # Fetch the Manifest file if it exists
        fetched_files << manifest_file if manifest_file

        fetched_files
      end

      private

      sig { returns(Dependabot::DependencyFile) }
      def project_file
        @project_file ||= T.let(
          fetch_file_if_present("Project.toml") ||
          fetch_file_if_present("JuliaProject.toml") ||
          raise(
            Dependabot::DependencyFileNotFound,
            "No Project.toml or JuliaProject.toml found."
          ),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def manifest_file
        @manifest_file ||= T.let(
          fetch_file_if_present("Manifest.toml") ||
                                     fetch_file_if_present("JuliaManifest.toml"),
          T.nilable(Dependabot::DependencyFile)
        )
      end
    end
  end
end

Dependabot::FileFetchers.register("julia", Dependabot::Julia::FileFetcher)
