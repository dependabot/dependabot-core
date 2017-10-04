# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Docker
      class Docker < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          (%w(Dockerfile) - filenames).empty?
        end

        def self.required_files_message
          "Repo must contain a Dockerfile."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << dockerfile
          fetched_files
        end

        def dockerfile
          @dockerfile ||= fetch_file_from_github("Dockerfile")
        end
      end
    end
  end
end
