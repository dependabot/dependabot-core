# typed: strong
# frozen_string_literal: true

require "dependabot/python/language"

module Dependabot
  module Uv
    # Both uv and Python ecosystems use the same Python language versions.
    # The Python version list is maintained in python/lib/dependabot/python/language.rb
    # and shared via this alias to avoid dual-maintenance.
    LANGUAGE = Python::LANGUAGE
    Language = Python::Language
  end
end
