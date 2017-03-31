# frozen_string_literal: true
require "./app/dependency_file_fetchers/base"

module DependencyFileFetchers
  class Ruby < Base
    def files
      @files ||= [
        fetch_file_from_github("Gemfile"),
        fetch_file_from_github("Gemfile.lock")
      ]
    end
  end
end
