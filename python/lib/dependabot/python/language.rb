# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/python/version"
require "dependabot/ecosystem"

module Dependabot
  module Python
    LANGUAGE = "python"

    class Language < Dependabot::Ecosystem::VersionManager
      extend T::Sig
      # These versions should match the versions specified at the top of `python/Dockerfile`
      PYTHON_3_13 = "3.13"
      PYTHON_3_12 = "3.12"
      PYTHON_3_11 = "3.11"
      PYTHON_3_10 = "3.10"
      PYTHON_3_9  = "3.9"
      PYTHON_3_8  = "3.8"

      DEPRECATED_VERSIONS = T.let([Version.new(PYTHON_3_8)].freeze, T::Array[Dependabot::Version])

      # Keep versions in ascending order
      SUPPORTED_VERSIONS = T.let([
        Version.new(PYTHON_3_9),
        Version.new(PYTHON_3_10),
        Version.new(PYTHON_3_11),
        Version.new(PYTHON_3_12),
        Version.new(PYTHON_3_13)
      ].freeze, T::Array[Dependabot::Version])

      sig do
        params(
          detected_version: String,
          raw_version: String,
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize(detected_version, raw_version, requirement = nil)
        super(
          LANGUAGE,
          Version.new(detected_version),
          Version.new(raw_version),
          DEPRECATED_VERSIONS,
          SUPPORTED_VERSIONS,
          requirement
        )
      end

      sig { override.returns(T::Boolean) }
      def deprecated?
        return false if unsupported?
        return false unless Dependabot::Experiments.enabled?(:python_3_8_deprecation_warning)

        deprecated_versions.include?(version)
      end

      sig { override.returns(T::Boolean) }
      def unsupported?
        return false unless Dependabot::Experiments.enabled?(:python_3_8_unsupported_error)

        supported_versions.all? { |supported| supported > version }
      end
    end
  end
end
