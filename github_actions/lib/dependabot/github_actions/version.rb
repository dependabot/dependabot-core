# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/utils"
require "dependabot/version"

module Dependabot
  module GithubActions
    class Version < Dependabot::Version
      extend T::Sig

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        version = Version.remove_leading_v(version)
        super
      end

      sig { override.params(version: VersionParameter).returns(Dependabot::GithubActions::Version) }
      def self.new(version)
        T.cast(super, Dependabot::GithubActions::Version)
      end

      sig { params(version: VersionParameter).returns(VersionParameter) }
      def self.remove_leading_v(version)
        return version unless version.to_s.match?(%r{\A(?:.*/)?v?([0-9])})

        version.to_s.sub(%r{\A(?:.*/)?v?}, "")
      end

      sig { params(version: VersionParameter).returns(T::Boolean) }
      def self.path_based?(version)
        version.to_s.match?(%r{\A.+/v?([0-9])})
      end

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.to_s.strip.empty?

        version = Version.remove_leading_v(version)
        super
      end
    end
  end
end

Dependabot::Utils
  .register_version_class("github_actions", Dependabot::GithubActions::Version)
