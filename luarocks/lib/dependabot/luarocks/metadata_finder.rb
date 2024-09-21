# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/source"

module Dependabot
  module LuaRocks
    class MetadataFinder < Dependabot::MetadataFinders::Base
      private

      def look_up_source
        Source.from_url("https://luarocks.org/#{dependency.name}-#{dependency.version}.src.rock")
      end
    end
  end
end

Dependabot::MetadataFinders.register("luarocks", Dependabot::LuaRocks::MetadataFinder)
