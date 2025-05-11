# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module AzurePipelines
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      # Azure Pipelines allows any YAML file to be used as a pipeline
      # But this covers the most common cases for now.
      FILENAME_PATTERN = /azure[-_]pipelines?\.ya?ml$/

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |f| f.match?(FILENAME_PATTERN) }
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain an azure-pipelines.yml or azure-pipelines.yaml file."
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_files
        fetched_files = fetch_azure_pipelines_files
        return fetched_files if fetched_files.any?

        raise Dependabot::DependencyFileNotFound.new(
          nil,
          "No Azure Pipelines files found in #{directory}"
        )
      end

      private

      sig { params(dir: String).returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_azure_pipelines_files(dir: ".")
        contents = repo_contents(dir: dir, raise_errors: false)

        # Find all matching files in the current directory
        pipelines_files = contents
                          .filter_map do |f|
          fetch_file_from_host(File.join(dir, f.name)) if f.type == "file" && f.name.match?(FILENAME_PATTERN)
        end

        # Also check all subdirectories recursively
        subdirs = contents
                  .select { |f| f.type == "dir" }
                  .map(&:name)

        # Recursively fetch files from subdirectories and flatten the results
        subdirs.each do |subdir|
          pipelines_files.concat(fetch_azure_pipelines_files(dir: File.join(dir, subdir)))
        end

        pipelines_files
      end
    end
  end
end

Dependabot::FileFetchers.register("azure_pipelines", Dependabot::AzurePipelines::FileFetcher)
