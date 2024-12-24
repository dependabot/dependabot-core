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

      sig { params(raw_version: String).void }
      def initialize(raw_version)
        super(
          LANGUAGE,
          Version.new(""),
          Version.new(raw_version)
        )
      end
    end
  end
end
