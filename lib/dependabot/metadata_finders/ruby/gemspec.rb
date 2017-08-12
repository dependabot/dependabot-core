# frozen_string_literal: true
require "dependabot/metadata_finders/ruby/bundler"

module Dependabot
  module MetadataFinders
    module Ruby
      class Gemspec < Dependabot::MetadataFinders::Ruby::Bundler
        # Identical to the Bundler metadata finder
      end
    end
  end
end
