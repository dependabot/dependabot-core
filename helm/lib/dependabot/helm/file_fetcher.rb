# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Helm
    class FileFetcher < Dependabot::FileFetchers::Base
      def self.required_files_in?(filenames)
        filenames.any? { |f| f == "Chart.yaml" }
      end

      def self.required_files_message
        "Repo must contain a Chart.yaml."
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files += chart_files

        return fetched_files if fetched_files.any?

        raise(
          Dependabot::DependencyFileNotFound,
          File.join(directory, "Chart.yaml")
        )
      end

      def chart_files
        files = repo_contents(raise_errors: false).select do |f|
          false if f.type != "file"
          true if f.name == "Chart.yaml"
        end

        @chart_files ||= files.map { |f| fetch_file_from_host(f.name) }
      end
    end
  end
end

Dependabot::FileFetchers.register("helm", Dependabot::Helm::FileFetcher)
