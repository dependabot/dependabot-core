# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/uv/version"
require "dependabot/ecosystem"

module Dependabot
  module Uv
    LANGUAGE = "python"

    class Language < Dependabot::Ecosystem::VersionManager
      extend T::Sig
      # This list must match the versions specified at the top of `python/Dockerfile`
      # ARG PY_3_13=3.13.2
      # When updating this list, also update python/lib/dependabot/python/language.rb
      PRE_INSTALLED_PYTHON_VERSIONS_RAW = %w(
        3.13.3
        3.12.10
        3.11.12
        3.10.17
        3.9.22
      ).freeze

      PRE_INSTALLED_PYTHON_VERSIONS = T.let(PRE_INSTALLED_PYTHON_VERSIONS_RAW.map do |v|
        Version.new(v)
      end.sort, T::Array[Version])

      PRE_INSTALLED_VERSIONS_MAP = T.let(
        PRE_INSTALLED_PYTHON_VERSIONS.to_h do |v|
          [Version.new(T.must(v.segments[0..1]).join(".")), v]
        end,
        T::Hash[Version, Version]
      )

      PRE_INSTALLED_HIGHEST_VERSION = T.let(T.must(PRE_INSTALLED_PYTHON_VERSIONS.max), Version)

      SUPPORTED_VERSIONS = T.let(
        PRE_INSTALLED_PYTHON_VERSIONS.map do |v|
          Version.new(T.must(v.segments[0..1]&.join(".")))
        end,
        T::Array[Version]
      )

      NON_SUPPORTED_HIGHEST_VERSION = "3.8"

      DEPRECATED_VERSIONS = T.let([Version.new(NON_SUPPORTED_HIGHEST_VERSION)].freeze, T::Array[Dependabot::Version])

      sig do
        params(
          detected_version: T.nilable(String),
          raw_version: T.nilable(String),
          requirement: T.nilable(Requirement)
        ).void
      end
      def initialize(detected_version:, raw_version: nil, requirement: nil)
        super(
          name: LANGUAGE,
          detected_version: detected_version ? major_minor_version(detected_version) : nil,
          version: raw_version ? Version.new(raw_version) : nil,
          deprecated_versions: DEPRECATED_VERSIONS,
          supported_versions: SUPPORTED_VERSIONS,
          requirement: requirement,
       )
      end

      private

      sig { params(version: String).returns(T.nilable(Version)) }
      def major_minor_version(version)
        return nil if version.empty?

        major_minor = T.let(T.must(Version.new(version).segments[0..1]&.join(".")), String)

        Version.new(major_minor)
      end
    end
  end
end
