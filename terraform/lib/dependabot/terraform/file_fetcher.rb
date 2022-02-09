# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/terraform/file_selector"

module Dependabot
  module Terraform
    class FileFetcher < Dependabot::FileFetchers::Base
      include FileSelector

      # https://www.terraform.io/docs/language/modules/sources.html#local-paths
      LOCAL_PATH_SOURCE = %r{source\s*=\s*['"](?<path>..?\/[^'"]+)}.freeze

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
        fetched_files += local_path_module_files(terraform_files)
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

      def local_path_module_files(files, dir: ".")
        terraform_files = []

        files.each do |file|
          terraform_file_local_module_details(file).each do |path|
            base_path = Pathname.new(File.join(dir, path)).cleanpath.to_path
            nested_terraform_files =
              repo_contents(dir: base_path).
              select { |f| f.type == "file" && f.name.end_with?(".tf") }.
              map { |f| fetch_file_from_host(File.join(base_path, f.name)) }
            terraform_files += nested_terraform_files
            terraform_files += local_path_module_files(nested_terraform_files, dir: path)
          end
        end

        # NOTE: The `support_file` attribute is not used but we set this to
        # match what we do in other ecosystems
        terraform_files.tap { |fs| fs.each { |f| f.support_file = true } }
      end

      def terraform_file_local_module_details(file)
        return [] unless file.name.end_with?(".tf")
        return [] unless file.content.match?(LOCAL_PATH_SOURCE)

        file.content.scan(LOCAL_PATH_SOURCE).flatten.map do |path|
          Pathname.new(path).cleanpath.to_path
        end
      end

      def lock_file
        @lock_file ||= fetch_file_if_present(".terraform.lock.hcl")
      end
    end
  end
end

Dependabot::FileFetchers.
  register("terraform", Dependabot::Terraform::FileFetcher)
