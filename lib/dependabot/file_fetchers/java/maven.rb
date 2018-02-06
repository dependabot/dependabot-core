# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Java
      class Maven < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          (%w(pom.xml) - filenames).empty?
        end

        def self.required_files_message
          "Repo must contain a pom.xml."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << pom
          fetched_files
        end

        def pom
          @pom ||= fetch_file_from_host("pom.xml")
        end
      end
    end
  end
end
