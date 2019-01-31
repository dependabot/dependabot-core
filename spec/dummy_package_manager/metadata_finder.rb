# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"

module DummyPackageManager
  class MetadataFinder < Dependabot::MetadataFinders::Base
    private

    def look_up_source; end
  end
end

Dependabot::MetadataFinders.
  register("dummy", DummyPackageManager::MetadataFinder)
