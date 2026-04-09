# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/python/requirement"
require "dependabot/utils"

module Dependabot
  module Uv
    # UV uses Python's requirement scheme, so we delegate to Python::Requirement
    Requirement = Dependabot::Python::Requirement
  end
end

Dependabot::Utils
  .register_requirement_class("uv", Dependabot::Uv::Requirement)
