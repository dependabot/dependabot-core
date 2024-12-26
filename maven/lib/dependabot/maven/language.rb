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

      sig { void }
      def initialize
        super(
          LANGUAGE,
          nil,
          nil
        )
      end
    end
  end
end
