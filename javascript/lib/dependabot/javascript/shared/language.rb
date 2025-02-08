# typed: strong
# frozen_string_literal: true

module Dependabot
  module Javascript
    module Shared
      class Language < Ecosystem::VersionManager
        extend T::Sig
        NAME = "javascript"

        SUPPORTED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

        DEPRECATED_VERSIONS = T.let([].freeze, T::Array[Dependabot::Version])

        sig do
          params(
            detected_version: T.nilable(String),
            raw_version: T.nilable(String),
            requirement: T.nilable(Requirement)
          ).void
        end
        def initialize(detected_version: nil, raw_version: nil, requirement: nil)
          super(
            name: NAME,
            detected_version: detected_version ? Version.new(detected_version) : nil,
            version: raw_version ? Version.new(raw_version) : nil,
            deprecated_versions: DEPRECATED_VERSIONS,
            supported_versions: SUPPORTED_VERSIONS,
            requirement: requirement
          )
        end

        sig { override.returns(T::Boolean) }
        def deprecated?
          false
        end

        sig { override.returns(T::Boolean) }
        def unsupported?
          false
        end
      end
    end
  end
end
