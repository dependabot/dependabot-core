# frozen_string_literal: true

require "dependabot/file_fetchers/java_script/npm"

module Dependabot
  module FileFetchers
    module JavaScript
      class Yarn < Dependabot::FileFetchers::JavaScript::Npm
        def self.required_files_in?(filenames)
          (%w(package.json yarn.lock) - filenames).empty?
        end

        def self.required_files_message
          "Repo must contain a package.json and a yarn.lock."
        end
      end
    end
  end
end
