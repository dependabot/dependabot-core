# frozen_string_literal: true
require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module JavaScript
      class Yarn < Dependabot::FileFetchers::Base
        def self.required_files
          %w(package.json yarn.lock)
        end
      end
    end
  end
end
