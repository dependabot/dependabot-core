# typed: strict
# frozen_string_literal: true

require "dependabot/version"

module Dependabot
  module Julia
    class Version < Dependabot::Version
      VERSION_PATTERN =
        T.let(/(?<v>\d+)(?:\.(?<v>\d+))*(?<l>[a-z]+)?(?<r>\d+)?/i, Regexp)

      sig { override.params(version: T.nilable(T.any(String, Integer, Gem::Version))).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.nil?

        version.to_s.match?(/\A#{VERSION_PATTERN}\z/o)
      end

      sig { override.params(version: T.nilable(T.any(String, Integer, Gem::Version))).void }
      def initialize(version)
        @version_string = T.let(version.to_s, String)
        version = version.gsub(/^v/, "") if version.is_a?(String)
        super
      end

      sig do
        override
          .params(version: T.nilable(T.any(String, Integer, Gem::Version)))
          .returns(Dependabot::Julia::Version)
      end
      def self.new(version)
        T.cast(super, Dependabot::Julia::Version)
      end
    end
  end
end
