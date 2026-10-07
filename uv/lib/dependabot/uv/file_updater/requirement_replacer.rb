# typed: strong
# frozen_string_literal: true

require "dependabot/python/file_updater/requirement_replacer"
require "dependabot/uv/file_updater"

module Dependabot
  module Uv
    class FileUpdater
      # UV uses the same requirement replacement logic as Python.
      # Both ecosystems share RequirementParser, NativeHelpers, and NameNormaliser
      # via aliases, so we reuse Python's implementation.
      RequirementReplacer = Dependabot::Python::FileUpdater::RequirementReplacer
    end
  end
end
