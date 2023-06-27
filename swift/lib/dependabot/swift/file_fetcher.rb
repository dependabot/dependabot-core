# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module Dependabot
  module Swift
    class FileFetcher < Dependabot::FileFetchers::Base
      def self.required_files_in?(filenames)
        raise NotImplementedError
      end

      def self.required_files_message
        raise NotImplementedError
      end

      private

      def fetch_files
        raise NotImplementedError
      end
    end
  end
end

Dependabot::FileFetchers.
  register("swift", Dependabot::Swift::FileFetcher)
