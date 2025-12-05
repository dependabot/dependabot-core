# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module Luarocks
    class Version < Dependabot::Version
      extend T::Sig

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.nil?

        super(normalize(version))
      end

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        normalized = self.class.normalize(version)
        super(normalized)
        @original_version = T.let(version.to_s, String)
      end

      sig { params(version: VersionParameter).returns(String) }
      def self.normalize(version)
        version.to_s.tr("-", ".")
      end

      sig { override.returns(String) }
      def to_s
        @original_version
      end

      sig { override.returns(String) }
      def to_semver
        @original_version
      end
    end
  end
end

Dependabot::Utils.register_version_class("luarocks", Dependabot::Luarocks::Version)
