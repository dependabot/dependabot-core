# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/maven/version"
require "dependabot/maven/requirement"

module Dependabot
  module Maven
    LANGUAGE = "java"

    class Language < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig do
        params(
          detected_version: String,
          raw_version: String
        ).void
      end
      def initialize(
        detected_version,
        raw_version
      )
        super(
          LANGUAGE,
          Version.new(detected_version),
          Version.new(raw_version)
        )
      end
    end
  end
end
