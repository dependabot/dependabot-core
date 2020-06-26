# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
module Dependabot
  module Paket
    class FileFetcher < Dependabot::FileFetchers::Base

      def self.required_files_in?(filenames)
        contains_paket_dependencies = filenames.any? { |f| f.eql?("paket.dependencies")}
        contains_paket_lock = filenames.any? { |f| f.eql?("paket.lock")}
        contains_paket_dependencies and contains_paket_lock
      end

      def self.required_files_message
        "Repo must contain a paket.dependencies and a paket.lock"
      end

      private

      def fetch_files
        fetched_files = []
        fetched_files
      end
    end
  end
end



Dependabot::FileFetchers.register("paket", Dependabot::Paket::FileFetcher)
