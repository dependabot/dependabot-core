# typed: strict
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Opam
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        # Check for opam files (opam or *.opam)
        filenames.any? { |f| f.match?(%r{^[^/]*\.opam$}) || f == "opam" }
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain an opam or *.opam file."
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = []

        # Fetch all opam files
        fetched_files += opam_files

        # Fetch lock file if present
        fetched_files << opam_lock_file if opam_lock_file

        # Ensure we have at least one opam file
        return fetched_files if fetched_files.any?

        raise(
          Dependabot::DependencyFileNotFound,
          File.join(directory, "*.opam")
        )
      end

      private

      sig { returns(T::Array[DependencyFile]) }
      def opam_files
        @opam_files ||= T.let(
          begin
            files = []

            # Fetch repo contents once
            contents = repo_contents(dir: directory)

            # Look for main 'opam' file and *.opam files
            contents.each do |file|
              next unless file.type == "file"
              next unless file.name == "opam" || file.name.end_with?(".opam")

              files << fetch_file_from_host(file.name)
            end

            files
          end,
          T.nilable(T::Array[DependencyFile])
        )
      end

      sig { returns(T.nilable(DependencyFile)) }
      def opam_lock_file
        @opam_lock_file ||= T.let(
          begin
            # Check if lockfile exists in repo contents
            contents = repo_contents(dir: directory)
            return nil unless contents.any? { |f| f.type == "file" && f.name == "opam.lock" }

            fetch_file_from_host("opam.lock")
          rescue Dependabot::DependencyFileNotFound, Dependabot::RepoNotFound, Octokit::NotFound
            nil
          end,
          T.nilable(DependencyFile)
        )
      end
    end
  end
end

Dependabot::FileFetchers
  .register("opam", Dependabot::Opam::FileFetcher)
