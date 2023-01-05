# frozen_string_literal: true

module Dependabot
  module Python
    module PythonVersions
      PRE_INSTALLED_PYTHON_VERSIONS = %w(
        3.11.0
      ).freeze

      # Due to an OpenSSL issue we can only install the following versions in
      # the Dependabot container.
      # NOTE: When adding one version, always doublecheck for additional releases: https://www.python.org/downloads/
      #
      # WARNING: 3.9.3 is purposefully omitted as it was recalled: https://www.python.org/downloads/release/python-393/
      SUPPORTED_VERSIONS = %w(
        3.11.1 3.11.0
        3.10.9 3.10.8 3.10.7 3.10.6 3.10.5 3.10.4 3.10.3 3.10.2 3.10.1 3.10.0
        3.9.16 3.9.15 3.9.14 3.9.13 3.9.12 3.9.11 3.9.10 3.9.9 3.9.8 3.9.7 3.9.6 3.9.5 3.9.4 3.9.2 3.9.1 3.9.0
        3.8.16 3.8.15 3.8.14 3.8.13 3.8.12 3.8.11 3.8.10 3.8.9 3.8.8 3.8.7 3.8.6 3.8.5 3.8.4 3.8.3 3.8.2 3.8.1 3.8.0
        3.7.16 3.7.15 3.7.14 3.7.13 3.7.12 3.7.11 3.7.10 3.7.9 3.7.8 3.7.7 3.7.6 3.7.5 3.7.4 3.7.3 3.7.2 3.7.1 3.7.0
        3.6.15 3.6.14 3.6.13 3.6.12 3.6.11 3.6.10 3.6.9 3.6.8 3.6.7 3.6.6 3.6.5 3.6.4 3.6.3 3.6.2 3.6.1 3.6.0
        3.5.10 3.5.8 3.5.7 3.5.6 3.5.5 3.5.4 3.5.3
      ).freeze

      # This list gets iterated through to find a valid version, so we have
      # the pre-installed versions listed first.
      SUPPORTED_VERSIONS_TO_ITERATE =
        [
          *PRE_INSTALLED_PYTHON_VERSIONS,
          *SUPPORTED_VERSIONS
        ].freeze
    end
  end
end
