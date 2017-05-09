# frozen_string_literal: true
require "bump/dependency_file_fetchers/base"

module Bump
  module DependencyFileFetchers
    class Javascript < Base
      def files
        @files ||= [
          fetch_file_from_github("package.json"),
          fetch_file_from_github("yarn.lock")
        ]
      end
    end
  end
end
