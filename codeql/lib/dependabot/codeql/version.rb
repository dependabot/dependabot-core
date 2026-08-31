# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module Codeql
    class Version < Dependabot::Version
      extend T::Sig

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        @version_string = T.let(version.to_s, String)
        super
      end

      sig { override.params(version: VersionParameter).returns(Dependabot::Codeql::Version) }
      def self.new(version)
        T.cast(super, Dependabot::Codeql::Version)
      end

      sig { override.returns(String) }
      def to_s
        @version_string
      end
    end
  end
end

Dependabot::Utils.register_version_class("codeql", Dependabot::Codeql::Version)
