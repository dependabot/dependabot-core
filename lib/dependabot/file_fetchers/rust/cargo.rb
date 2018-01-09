# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Rust
      class Cargo < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          (%w(Cargo.toml Cargo.lock) - filenames).empty?
        end

        def self.required_files_message
          "Repo must contain a Cargo.toml and Cargo.lock."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << cargo_toml
          fetched_files << cargo_lock
          fetched_files
        end

        def cargo_toml
          @cargo_toml ||= fetch_file_from_github("Cargo.toml")
        end

        def cargo_lock
          @cargo_lock ||= fetch_file_from_github("Cargo.lock")
        end
      end
    end
  end
end
