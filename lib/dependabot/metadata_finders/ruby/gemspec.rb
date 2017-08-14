# frozen_string_literal: true
require "dependabot/metadata_finders/ruby/bundler"

module Dependabot
  module MetadataFinders
    module Ruby
      # Inherit from MetadataFinder::Ruby::Bundler
      class Gemspec < Dependabot::MetadataFinders::Ruby::Bundler
      end
    end
  end
end
