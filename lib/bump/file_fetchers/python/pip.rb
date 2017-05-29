# frozen_string_literal: true
require "bump/file_fetchers/base"

module Bump
  module FileFetchers
    module Python
      class Pip < Bump::FileFetchers::Base
        def self.required_files
          %w(requirements.txt)
        end
      end
    end
  end
end
