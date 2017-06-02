# frozen_string_literal: true
require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Php
      class Composer < Dependabot::FileFetchers::Base
        def self.required_files
          %w(composer.json composer.lock)
        end
      end
    end
  end
end
