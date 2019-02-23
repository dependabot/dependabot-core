# frozen_string_literal: true

module Dependabot
  module Python
    module PythonVersions
      PRE_INSTALLED_PYTHON_VERSIONS = %w(
        3.6.8 2.7.15
      ).freeze

      # Due to an OpenSSL issue we can only install the following versions in
      # the Dependabot container.
      SUPPORTED_VERSIONS = %w(
        3.7.2 3.7.1 3.7.0
        3.6.8 3.6.7 3.6.6 3.6.5 3.6.4 3.6.3 3.6.2 3.6.1 3.6.0
        3.5.6 3.5.5 3.5.4 3.5.3
        2.7.15 2.7.14 2.7.13
      ).freeze

      # This list gets iterated through to find a valid version, so we have
      # the two pre-installed versions listed first.
      SUPPORTED_VERSIONS_TO_ITERATE =
        [
          *PRE_INSTALLED_PYTHON_VERSIONS,
          *SUPPORTED_VERSIONS
        ].freeze
    end
  end
end
