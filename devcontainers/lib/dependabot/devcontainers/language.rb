# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/ecosystem"
require "dependabot/devcontainers/version"

module Dependabot
  module Devcontainers
    LANGUAGE = "node"

    class Language < Dependabot::Ecosystem::VersionManager
      extend T::Sig

      sig { params(raw_version: String).void }
      def initialize(raw_version)
        super(
          name: LANGUAGE,
          version: Version.new(raw_version))
      end
    end
  end
end
