# typed: strong
# frozen_string_literal: true

require "dependabot/python/native_helpers"

module Dependabot
  module Uv
    # Uv and Python ecosystems share the same native Python helpers.
    # Both point to the same helpers/python directory.
    NativeHelpers = Python::NativeHelpers
  end
end
