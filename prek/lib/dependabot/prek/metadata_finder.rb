# typed: strong
# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/pre_commit/metadata_finder"

module Dependabot
  module Prek
    # Hook sources are git repositories, resolved the same way as pre-commit.
    class MetadataFinder < Dependabot::PreCommit::MetadataFinder
    end
  end
end

Dependabot::MetadataFinders
  .register("prek", Dependabot::Prek::MetadataFinder)
