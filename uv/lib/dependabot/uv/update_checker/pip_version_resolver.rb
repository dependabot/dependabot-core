# typed: strong
# frozen_string_literal: true

require "dependabot/python/update_checker/pip_version_resolver"
require "dependabot/uv/update_checker"

module Dependabot
  module Uv
    class UpdateChecker
      # UV uses the same pip version resolution logic as Python.
      # Both ecosystems share LanguageVersionManager, LatestVersionFinder,
      # and PythonRequirementParser via aliases, so we reuse Python's implementation.
      PipVersionResolver = Dependabot::Python::UpdateChecker::PipVersionResolver
    end
  end
end
