# typed: strict
# frozen_string_literal: true

require "dependabot/version"

module Dependabot
  module Julia
    class Version < Dependabot::Version
      extend T::Sig

      sig { params(version: T.nilable(T.any(String, Integer, Gem::Version))).void }
      def initialize(version)
        @version_string = T.let(version.to_s, String)
        version = version.gsub(/^v/, "") if version.is_a?(String)
        super
      end
    end
  end
end
