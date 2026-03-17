# typed: strong
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module Mise
    class Version < Dependabot::Version
      extend T::Sig

      sig { override.params(version: T.nilable(T.any(String, Integer, ::Gem::Version))).void }
      def initialize(version)
        @version_string = T.let(version.to_s, String)
        super
      end

      # Preserve the original version string. Gem::Version may normalize version
      # segments internally, which would break round-trip fidelity when the file
      # updater writes the version back to mise.toml.
      sig { returns(String) }
      def to_s
        @version_string
      end

      sig { returns(String) }
      def inspect
        "#<Dependabot::Mise::Version #{@version_string.inspect}>"
      end
    end
  end
end

Dependabot::Utils.register_version_class("mise", Dependabot::Mise::Version)
