# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/cargo/version"

module Dependabot
  module Cargo
    LANGUAGE = "rust"

    class Language < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { params(raw_version: String).void }
      def initialize(raw_version)
        super(
          LANGUAGE,
          Version.new(raw_version)
        )
      end
    end
  end
end
