# frozen_string_literal: true
require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Python
      class Pip < Dependabot::FileFetchers::Base
        def self.required_files
          %w(requirements.txt)
        end
      end
    end
  end
end
