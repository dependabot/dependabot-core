# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Ansible
    class FileFetcher < Dependabot::FileFetchers::Base

      def self.required_files_in?(filenames)
        filenames.include?("requirements.yml")
      end

      def self.required_files_message
        "Repo must contain a requirements.yml file."
      end

      private

      def fetch_files
        [requirements_yml_files]
      end

      def requirements_yml_files
        @requirements_yml_files ||= fetch_file_from_host("requirements.yml")
      end

    end
  end
end

Dependabot::FileFetchers.register("ansible", Dependabot::Ansible::FileFetcher)
