# frozen_string_literal: true
require "bump/dependency_file_fetchers/base"

module Bump
  module DependencyFileFetchers
    module JavaScript
      class Yarn < Bump::DependencyFileFetchers::Base
        def self.required_files
          %w(package.json yarn.lock)
        end
      end
    end
  end
end
