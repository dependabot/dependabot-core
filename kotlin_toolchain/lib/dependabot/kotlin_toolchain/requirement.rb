# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/gradle/requirement"
require "dependabot/kotlin_toolchain/version"
require "dependabot/utils"

module Dependabot
  module KotlinToolchain
    class Requirement < Dependabot::Gradle::Requirement
      extend T::Sig

      sig { override.params(obj: T.any(Gem::Version, String)).returns([String, Gem::Version]) }
      def self.parse(obj)
        operator, version = super
        [operator, Version.new(version.to_s)]
      end

      sig { override.params(version: Gem::Version).returns(T::Boolean) }
      def satisfied_by?(version)
        super(Version.new(version.to_s))
      end
    end
  end
end

Dependabot::Utils.register_requirement_class(
  "kotlin_toolchain",
  Dependabot::KotlinToolchain::Requirement
)
