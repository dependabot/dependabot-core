# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/bundler/version"
require "dependabot/ecosystem"

module Dependabot
  module Bundler
    LANGUAGE = "ruby"

    class Language < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { params(raw_version: String, requirement: T.nilable(Requirement)).void }
      def initialize(raw_version, requirement = nil)
        super(
          name: LANGUAGE,
          version: Version.new(raw_version),
          requirement: requirement)
      end
    end
  end
end
