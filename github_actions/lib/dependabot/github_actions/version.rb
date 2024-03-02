# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/utils"
require "dependabot/version"

module Dependabot
  module GithubActions
    class Version < Dependabot::Version
      extend T::Sig

      sig do
        override
          .overridable
          .params(
            version: T.any(
              String,
              Integer,
              Float,
              Gem::Version,
              NilClass
            )
          )
          .void
      end
      def initialize(version)
        version = Version.remove_leading_v(version)
        super
      end

      sig do
        params(
          version: T.any(
            String,
            Integer,
            Float,
            Gem::Version,
            NilClass
          )
        ).returns(
          T.any(
            String,
            Integer,
            Float,
            Gem::Version,
            NilClass
          )
        )
      end
      def self.remove_leading_v(version)
        return version unless version.to_s.match?(/\Av([0-9])/)

        version.to_s.delete_prefix("v")
      end

      sig do
        override
          .params(
            version: T.any(
              String,
              Integer,
              Float,
              Gem::Version,
              NilClass
            )
          )
          .returns(T::Boolean)
      end
      def self.correct?(version)
        version = Version.remove_leading_v(version)
        super
      end
    end
  end
end

Dependabot::Utils
  .register_version_class("github_actions", Dependabot::GithubActions::Version)
