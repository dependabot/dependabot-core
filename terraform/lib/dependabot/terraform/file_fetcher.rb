# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/terraform/file_selector"

module Dependabot
  module Terraform
    class FileFetcher < Dependabot::FileFetchers::Base
      include FileSelector

      def self.required_files_in?(filenames)
        filenames.any? { |f| f.end_with?(".tf", ".hcl") }
      end

      def self.required_files_message
        "Repo must contain a Terraform configuration file."
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files += terraform_files
        fetched_files += terragrunt_files
        fetched_files += [lock_file] if lock_file

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

      def terragrunt_files
        @terragrunt_files ||=
          repo_contents(raise_errors: false).
          select { |f| f.type == "file" && terragrunt_file?(f.name) }.
          map { |f| fetch_file_from_host(f.name) }
      end

      def lock_file
        @lock_file ||= fetch_file_if_present(".terraform.lock.hcl")
      end
    end
  end
end

Dependabot::FileFetchers.
  register("terraform", Dependabot::Terraform::FileFetcher)
