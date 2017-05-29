# frozen_string_literal: true
require "bump/file_fetchers/base"

module Bump
  module FileFetchers
    module Ruby
      class Bundler < Bump::FileFetchers::Base
        def self.required_files
          %w(Gemfile Gemfile.lock)
        end
      end
    end
  end
end
