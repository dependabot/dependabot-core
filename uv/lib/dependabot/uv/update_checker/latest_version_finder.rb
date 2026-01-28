# typed: strong
# frozen_string_literal: true

require "dependabot/python/update_checker/latest_version_finder"
require "dependabot/uv/update_checker"

module Dependabot
  module Uv
    class UpdateChecker
      # UV uses the same PyPI registry for package lookups as Python.
      # Both ecosystems use the same PackageDetailsFetcher (via Uv::Package alias)
      # and identical LatestVersionFinder logic, so we reuse Python's implementation.
      LatestVersionFinder = Dependabot::Python::UpdateChecker::LatestVersionFinder
    end
  end
end
