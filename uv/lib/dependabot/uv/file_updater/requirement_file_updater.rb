# typed: strong
# frozen_string_literal: true

require "dependabot/python/file_updater/requirement_file_updater"
require "dependabot/uv/file_updater"

module Dependabot
  module Uv
    class FileUpdater
      # UV uses the same requirement file update logic as Python.
      # Both ecosystems share RequirementReplacer and NativeHelpers
      # via aliases, so we reuse Python's implementation.
      RequirementFileUpdater = Dependabot::Python::FileUpdater::RequirementFileUpdater
    end
  end
end
