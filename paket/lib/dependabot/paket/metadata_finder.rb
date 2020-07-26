# frozen_string_literal: true

require "nokogiri"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module Dependabot
  module Paket
    class MetadataFinder < Dependabot::MetadataFinders::Base

    end
  end
end

Dependabot::MetadataFinders.register("paket", Dependabot::Paket::MetadataFinder)
