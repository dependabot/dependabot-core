# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/python/requirement_parser"

module Dependabot
  module Uv
    # UV uses the same Python requirement parsing regex patterns (PEP 508)
    RequirementParser = Dependabot::Python::RequirementParser
  end
end
