# frozen_string_literal: true
require "bump/dependency_file_fetchers/base"

module Bump
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
end
