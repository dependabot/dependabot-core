# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/gradle/version"

module Dependabot
  module Gradle
    LANGUAGE = "jvm_languages"

    class Language < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { void }
      def initialize
        super(LANGUAGE)
      end
    end
  end
end
