# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Puppet
    class FileFetcher < Dependabot::FileFetchers::Base
      def self.required_files_in?(filenames)
        filenames.include?("Puppetfile")
      end

      def self.required_files_message
        "Repo must contain a Puppetfile."
      end

      private

      def fetch_files
        fetched_files = [puppet_file]
        fetched_files
      end

      def puppet_file
        @puppet_file ||= fetch_file_from_host("Puppetfile")
      end
    end
  end
end

Dependabot::FileFetchers.register("puppet", Dependabot::Puppet::FileFetcher)
