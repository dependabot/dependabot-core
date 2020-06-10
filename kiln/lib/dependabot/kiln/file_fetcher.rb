# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Kiln
    class FileFetcher < Dependabot::FileFetchers::Base
      def self.required_files_in?(filenames)
        (%w(Kilnfile Kilnfile.lock) - filenames).empty?
      end

      def self.required_files_message
        "Repo must contain both Kilnfile and Kilnfile.lock"
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files << kilnfile if kilnfile
        fetched_files << kilnlockfile if kilnlockfile

        unless kilnfile
          raise(
              Dependabot::DependencyFileNotFound,
              File.join(directory, "Kilnfile")
          )
        end

        unless kilnlockfile
          raise(
              Dependabot::DependencyFileNotFound,
              File.join(directory, "Kilnfile.lock")
          )
        end

        fetched_files
      end

      def kilnfile
        @kilnfile ||= fetch_file_if_present("Kilnfile")
      end

      def kilnlockfile
        @kilnlockfile ||= fetch_file_if_present("Kilnfile.lock")
      end

    end
  end
end

Dependabot::FileFetchers.register("kiln", Dependabot::Kiln::FileFetcher)
