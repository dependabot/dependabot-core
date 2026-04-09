# typed: strong
# frozen_string_literal: true

require "dependabot/python/language_version_manager"

module Dependabot
  module Uv
    # Uv and Python ecosystems share the same Python version management logic.
    # This alias ensures uv benefits from improvements in Python's implementation,
    # including bug fixes like the guard clause in python_version_matching_imputed_requirements.
    LanguageVersionManager = Python::LanguageVersionManager
  end
end
