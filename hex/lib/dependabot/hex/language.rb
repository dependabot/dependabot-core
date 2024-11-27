# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/hex/version"

module Dependabot
  module Hex
    LANGUAGE = "elixir"

    class Language < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { params(raw_version: String, requirement: T.nilable(Requirement)).void }
      def initialize(raw_version, requirement = nil)
        super(LANGUAGE, Version.new(raw_version), [], [], requirement)
      end
    end
  end
end
