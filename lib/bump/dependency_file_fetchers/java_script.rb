# frozen_string_literal: true
require "bump/dependency_file_fetchers/base"

module Bump
  module DependencyFileFetchers
    class JavaScript < Base
      def required_files
        %w(package.json yarn.lock)
      end
    end
  end
end
