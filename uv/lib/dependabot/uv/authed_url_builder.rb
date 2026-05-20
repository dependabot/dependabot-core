# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/python/authed_url_builder"

module Dependabot
  module Uv
    # UV uses the same authenticated URL building logic as Python
    AuthedUrlBuilder = Dependabot::Python::AuthedUrlBuilder
  end
end
