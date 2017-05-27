# frozen_string_literal: true
require "bump/dependency_file_fetchers/base"

module Bump
  module DependencyFileFetchers
    module Ruby
      class Bundler < Bump::DependencyFileFetchers::Base
        def self.required_files
          %w(Gemfile Gemfile.lock)
        end
      end
    end
  end
end
