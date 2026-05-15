# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/python/metadata_finder"
require "dependabot/metadata_finders"

module Dependabot
  module Uv
    # UV uses Python's PyPI metadata lookup, so we delegate to Python::MetadataFinder
    MetadataFinder = Dependabot::Python::MetadataFinder
  end
end

Dependabot::MetadataFinders
  .register("uv", Dependabot::Uv::MetadataFinder)
