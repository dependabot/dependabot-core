# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module PreCommit
    class Version < Dependabot::Version
      extend T::Sig

      # pre-commit revs are commonly git tags with a leading "v" (e.g. "v1.2.3").
      # Strip it so these revs can be compared and classified like plain versions.
      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        version = Version.remove_leading_v(version)
        super
      end

      sig { override.params(version: VersionParameter).returns(Dependabot::PreCommit::Version) }
      def self.new(version)
        T.cast(super, Dependabot::PreCommit::Version)
      end

      sig { params(version: VersionParameter).returns(T::Boolean) }
      def self.v_prefixed?(version)
        version.to_s.match?(/\Av\d/i)
      end

      sig { params(version: VersionParameter).returns(VersionParameter) }
      def self.remove_leading_v(version)
        return version unless v_prefixed?(version)

        version.to_s[1..]
      end

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.nil? || version.to_s.strip.empty?

        super(remove_leading_v(version))
      end
    end
  end
end

Dependabot::Utils
  .register_version_class("pre_commit", Dependabot::PreCommit::Version)
