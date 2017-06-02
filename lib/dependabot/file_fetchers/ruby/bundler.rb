# frozen_string_literal: true
require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Ruby
      class Bundler < Dependabot::FileFetchers::Base
        def self.required_files
          %w(Gemfile Gemfile.lock)
        end
      end
    end
  end
end
