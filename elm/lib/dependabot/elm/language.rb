# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/elm/version"
require "dependabot/ecosystem"

module Dependabot
  module Elm
    LANGUAGE = "elm"

    class Language < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { params(raw_version: String, requirement: T.nilable(Requirement)).void }
      def initialize(raw_version, requirement = nil)
        super(
          LANGUAGE,
          nil,
          Version.new(raw_version),
          [],
          [],
          requirement
        )
      end

      sig { returns(T::Boolean) }
      def deprecated?
        false
      end

      sig { returns(T::Boolean) }
      def unsupported?
        false
      end
    end
  end
end
