# frozen_string_literal: true
require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Cocoa
      class CocoaPods < Dependabot::FileFetchers::Base
        def self.required_files
          %w(Podfile Podfile.lock)
        end
      end
    end
  end
end
