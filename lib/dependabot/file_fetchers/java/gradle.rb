# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Java
      class Gradle < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          filenames.include?("build.gradle")
        end

        def self.required_files_message
          "Repo must contain a build.gradle."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << buildfile
          fetched_files
        end

        def buildfile
          @buildfile ||= fetch_file_from_host("build.gradle")
        end
      end
    end
  end
end
