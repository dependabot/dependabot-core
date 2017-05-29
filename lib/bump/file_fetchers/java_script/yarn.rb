# frozen_string_literal: true
require "bump/file_fetchers/base"

module Bump
  module FileFetchers
    module JavaScript
      class Yarn < Bump::FileFetchers::Base
        def self.required_files
          %w(package.json yarn.lock)
        end
      end
    end
  end
end
