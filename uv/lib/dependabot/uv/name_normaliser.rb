# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/python/name_normaliser"

module Dependabot
  module Uv
    # UV uses the same Python package name normalization (PEP 503)
    NameNormaliser = Dependabot::Python::NameNormaliser
  end
end
