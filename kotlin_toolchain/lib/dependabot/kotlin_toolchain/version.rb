# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/gradle/version"
require "dependabot/utils"

module Dependabot
  module KotlinToolchain
    # Kotlin Toolchain publishes Maven-style versions, including forms such as
    # 0.12.0-dev-4188. Gradle's version implementation already follows Maven
    # ordering and preserves the original spelling.
    class Version < Dependabot::Gradle::Version
      extend T::Sig
    end
  end
end

Dependabot::Utils.register_version_class(
  "kotlin_toolchain",
  Dependabot::KotlinToolchain::Version
)
