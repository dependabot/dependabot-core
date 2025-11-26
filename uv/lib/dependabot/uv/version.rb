# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/python/version"
require "dependabot/utils"

module Dependabot
  module Uv
    # UV uses Python's version scheme, so we delegate to Python::Version
    Version = Dependabot::Python::Version
  end
end

Dependabot::Utils
  .register_version_class("uv", Dependabot::Uv::Version)
