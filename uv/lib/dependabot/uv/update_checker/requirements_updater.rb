# typed: strong
# frozen_string_literal: true

require "dependabot/python/update_checker/requirements_updater"
require "dependabot/uv/update_checker"

module Dependabot
  module Uv
    class UpdateChecker
      # UV uses the same requirements update logic as Python.
      # Both ecosystems share Version and Requirement classes (via aliases),
      # so we reuse Python's RequirementsUpdater implementation.
      RequirementsUpdater = Dependabot::Python::UpdateChecker::RequirementsUpdater
    end
  end
end
