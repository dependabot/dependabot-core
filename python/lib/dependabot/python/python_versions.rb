# frozen_string_literal: true

module Dependabot
  module Python
    module PythonVersions
      # Poetry doesn't handle Python versions, so we have to do so manually
      # (checking from a list of versions Poetry supports).
      # This list gets iterated through to find a valid version, so we have
      # the two pre-installed versions listed first.
      PYTHON_VERSIONS = %w(
        3.6.8 2.7.15
        3.7.2 3.7.1 3.7.0
        3.6.8 3.6.7 3.6.6 3.6.5 3.6.4 3.6.3 3.6.2 3.6.1 3.6.0
        3.5.6 3.5.5 3.5.4 3.5.3 3.5.2 3.5.1 3.5.0
        3.4.9 3.4.8 3.4.7 3.4.6 3.4.5 3.4.4 3.4.3 3.4.2 3.4.1 3.4.0
        2.7.15 2.7.14 2.7.13 2.7.12 2.7.11 2.7.10 2.7.9 2.7.8 2.7.7 2.7.6 2.7.5
        2.7.4 2.7.3 2.7.2 2.7.1 2.7
      ).freeze

      PRE_INSTALLED_PYTHON_VERSIONS = %w(
        3.6.8 2.7.15
      ).freeze
    end
  end
end
