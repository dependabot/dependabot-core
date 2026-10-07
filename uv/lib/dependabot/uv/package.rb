# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/python/package/package_registry_finder"
require "dependabot/python/package/package_details_fetcher"

module Dependabot
  module Uv
    # UV uses the same Python package registry handling (PyPI)
    module Package
      # Re-export constants from Python::Package for backward compatibility
      CREDENTIALS_USERNAME = Python::Package::CREDENTIALS_USERNAME
      CREDENTIALS_PASSWORD = Python::Package::CREDENTIALS_PASSWORD
      APPLICATION_JSON = Python::Package::APPLICATION_JSON
      APPLICATION_TEXT = Python::Package::APPLICATION_TEXT
      CPYTHON = Python::Package::CPYTHON
      PYTHON = Python::Package::PYTHON
      UNKNOWN = Python::Package::UNKNOWN
      MAIN_PYPI_INDEXES = Python::Package::MAIN_PYPI_INDEXES
      VERSION_REGEX = Python::Package::VERSION_REGEX

      PackageRegistryFinder = Dependabot::Python::Package::PackageRegistryFinder
      PackageDetailsFetcher = Dependabot::Python::Package::PackageDetailsFetcher
    end
  end
end
