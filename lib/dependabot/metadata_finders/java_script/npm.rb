# frozen_string_literal: true
require "dependabot/metadata_finders/java_script/yarn"

module Dependabot
  module MetadataFinders
    module JavaScript
      class Npm < Dependabot::MetadataFinders::JavaScript::Yarn
      end
    end
  end
end
