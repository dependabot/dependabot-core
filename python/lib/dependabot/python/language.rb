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
          raw_version: T.nilable(String),
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize(detected_version:, raw_version: nil, requirement: nil)
        super(
          name: LANGUAGE,
          detected_version: major_minor_version(detected_version),
          version: raw_version ? Version.new(raw_version) : nil,
          deprecated_versions: DEPRECATED_VERSIONS,
          supported_versions: SUPPORTED_VERSIONS,
          requirement: requirement,
       )
      end

      sig { override.returns(T::Boolean) }
      def deprecated?
        return false unless detected_version
        return false if unsupported?
        return false unless Dependabot::Experiments.enabled?(:python_3_8_deprecation_warning)

        deprecated_versions.include?(detected_version)
      end

      sig { override.returns(T::Boolean) }
      def unsupported?
        return false unless detected_version
        return false unless Dependabot::Experiments.enabled?(:python_3_8_unsupported_error)

        supported_versions.all? { |supported| supported > detected_version }
      end

      private

      sig { params(version: String).returns(Dependabot::Python::Version) }
      def major_minor_version(version)
        major_minor = T.let(T.must(Version.new(version).segments[0..1]&.join(".")), String)

        Version.new(major_minor)
      end
    end
  end
end
