# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
module Dependabot
  module Paket
    class FileFetcher < Dependabot::FileFetchers::Base

      PAKET_DEPENDENCIES_FILE = "paket.dependencies"
      PAKET_LOCK_FILE = "paket.lock"
      def self.required_files_in?(filenames)
        contains_paket_dependencies = filenames.any? { |f| f.eql?(PAKET_DEPENDENCIES_FILE)}
        contains_paket_lock = filenames.any? { |f| f.eql?(PAKET_LOCK_FILE)}
        contains_paket_dependencies and contains_paket_lock
      end

      def self.required_files_message
        "Repo must contain a %s and a %s" % [PAKET_DEPENDENCIES_FILE, PAKET_LOCK_FILE]
      end

      private

      def fetch_files
        fetched_files = []

        fetched_files << paket_dependencies if paket_dependencies
        fetched_files << paket_lock if paket_lock

        fetched_files
      end

      def paket_dependencies
        @paket_dependencies ||= fetch_file_if_present(PAKET_DEPENDENCIES_FILE)
      end

      def paket_lock
        @paket_lock ||= fetch_file_if_present(PAKET_LOCK_FILE)
      end

    end
  end
end



Dependabot::FileFetchers.register("paket", Dependabot::Paket::FileFetcher)
