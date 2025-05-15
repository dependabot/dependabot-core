# typed: true
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Cargo
    class RegistryFetcher < Dependabot::FileFetchers::Base
      def self.required_files_in?(filenames)
        filenames.include?("config.json")
      end

      def self.required_files_message
        "Repo must contain a config.json"
      end

      def dl
        parsed_config_json["dl"].chomp("/")
      end

      def api
        parsed_config_json["api"].chomp("/")
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files << config_json
      end

      def parsed_config_json
        @parsed_config_json ||= JSON.parse(config_json.content)
      end

      def config_json
        @config_json ||= fetch_file_from_host("config.json")
      end
    end
  end
end
