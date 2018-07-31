# frozen_string_literal: true

require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Elm
      class ElmPackage < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          (required_files - filenames).empty?
        end

        def self.required_files_message
          "Repo must contain an " + required_files.join(" and an ")
        end

        private

        def fetch_files
          required_files.
          	map {|filename| fetch_file_from_host(filename)}
        end

        def required_files
        	[elm_package]
        end

        def elm_package
        	"elm-package.json"
        end

        def exact_deps
          # This file is not recommended to be checked in
          # we shouldn't deal with it.
          #
          # Leaving this here merely to document.
        	"elm-stuff/exact-dependencies.json"
        end
      end
    end
  end
end
