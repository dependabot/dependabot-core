# frozen_string_literal: true

require "nokogiri"
require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/file_fetchers/base"

module Dependabot
  module Sbt
    class MetadataFinder < Dependabot::MetadataFinders::Base
    end
  end
end

Dependabot::MetadataFinders.register("sbt", Dependabot::Sbt::MetadataFinder)
