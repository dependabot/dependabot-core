# frozen_string_literal: true
require "bump/dependency_file_fetchers/base"

module Bump
  module DependencyFileFetchers
    class Python < Base
      def required_files
        %w(requirements.txt)
      end
    end
  end
end
