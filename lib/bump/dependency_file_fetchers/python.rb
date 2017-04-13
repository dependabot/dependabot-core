# frozen_string_literal: true
require "bump/dependency_file_fetchers/base"

module Bump
  module DependencyFileFetchers
    class Python < Base
      def files
        @files ||= [
          fetch_file_from_github("requirements.txt")
        ]
      end
    end
  end
end
