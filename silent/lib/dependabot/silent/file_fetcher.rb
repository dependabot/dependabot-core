# typed: true
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module SilentPackageManager
  class FileFetcher < Dependabot::FileFetchers::Base
    def fetch_files
      [manifest].compact
    end

    private

    def manifest
      fetch_file_if_present("manifest.json")
    end
  end
end

Dependabot::FileFetchers
  .register("silent", SilentPackageManager::FileFetcher)
