# frozen_string_literal: true
require "bump/file_fetchers/base"

module Bump
  module FileFetchers
    module Php
      class Composer < Bump::FileFetchers::Base
        def self.required_files
          %w(composer.json composer.lock)
        end
      end
    end
  end
end
