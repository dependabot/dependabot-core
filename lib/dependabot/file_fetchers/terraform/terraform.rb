# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Terraform
      class Terraform < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          filenames.any? { |f| f.end_with?(".tf") }
        end

        def self.required_files_message
          "Repo must contain a Terraform configuration file."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files += terraform_files

          return fetched_files if fetched_files.any?

          raise(
            Dependabot::DependencyFileNotFound,
            File.join(directory, "<anything>.tf")
          )
        end

        def terraform_files
          @terraform_files ||=
            repo_contents(raise_errors: false).
            select { |f| f.type == "file" && f.name.end_with?(".tf") }.
            map { |f| fetch_file_from_host(f.name) }
        end
      end
    end
  end
end
