# frozen_string_literal: true
require "dependabot/file_fetchers/base"

module Dependabot
  module FileFetchers
    module Elixir
      class Hex < Dependabot::FileFetchers::Base
        def self.required_files
          %w(mix.exs mix.lock)
        end
      end
    end
  end
end
