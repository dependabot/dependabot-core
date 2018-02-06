# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Elixir
      class Hex < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          (%w(mix.exs mix.lock) - filenames).empty?
        end

        def self.required_files_message
          "Repo must contain a mix.exs and a mix.lock."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << mixfile
          fetched_files << lockfile
          fetched_files
        end

        def mixfile
          @mixfile ||= fetch_file_from_host("mix.exs")
        end

        def lockfile
          @lockfile ||= fetch_file_from_host("mix.lock")
        end
      end
    end
  end
end
