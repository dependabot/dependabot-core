# typed: true
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"

module DummyPackageManager
  class FileFetcher < Dependabot::FileFetchers::Base
    def fetch_files
      [a_dummy, b_dummy].compact
    end

    private

    def a_dummy
      fetch_file_if_present("a.dummy")
    end

    def b_dummy
      fetch_file_if_present("b.dummy")
    end
  end
end

Dependabot::FileFetchers
  .register("dummy", DummyPackageManager::FileFetcher)
