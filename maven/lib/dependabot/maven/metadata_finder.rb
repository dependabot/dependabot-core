# typed: strong
# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/maven/shared/shared_metadata_finder"
require "sorbet-runtime"

module Dependabot
  module Maven
    class MetadataFinder < Dependabot::Maven::Shared::SharedMetadataFinder
      extend T::Sig
    end
  end
end

Dependabot::MetadataFinders
  .register("maven", Dependabot::Maven::MetadataFinder)
