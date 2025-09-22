# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/version"
require "dependabot/utils"

# Elixir versions can include build information, which Ruby can't parse.
# This class augments Gem::Version with build information.
# See https://hexdocs.pm/elixir/Version.html for details.

module Dependabot
  module Hex
    class Version < Dependabot::Version
      extend T::Sig

      sig { returns(T.nilable(String)) }
      attr_reader :build_info

      VERSION_PATTERN = T.let(Gem::Version::VERSION_PATTERN + '(\+[0-9a-zA-Z\-.]+)?', String)
      ANCHORED_VERSION_PATTERN = T.let(/\A\s*(#{VERSION_PATTERN})?\s*\z/, Regexp)

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.nil?

        version.to_s.match?(ANCHORED_VERSION_PATTERN)
      end

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        @version_string = T.let(version.to_s, String)

        version, @build_info = version.to_s.split("+") if version.to_s.include?("+")
        @build_info = T.let(@build_info, T.nilable(String))

        super
      end

      sig { override.returns(String) }
      def to_s
        @version_string
      end

      sig { override.returns(String) }
      def inspect # :nodoc:
        "#<#{self.class} #{@version_string}>"
      end

      sig { params(other: T.untyped).returns(T.nilable(Integer)) }
      def <=>(other)
        version_comparison = super
        return version_comparison unless version_comparison&.zero?

        return build_info.nil? ? 0 : 1 unless other.is_a?(Hex::Version)

        # Build information comparison
        lhsegments = build_info.to_s.split(".").map(&:downcase)
        rhsegments = other.build_info.to_s.split(".").map(&:downcase)
        limit = [lhsegments.count, rhsegments.count].min

        lhs = ["1", *lhsegments.first(limit)].join(".")
        rhs = ["1", *rhsegments.first(limit)].join(".")

        local_comparison = Gem::Version.new(lhs) <=> Gem::Version.new(rhs)

        return local_comparison unless local_comparison&.zero?

        lhsegments.count <=> rhsegments.count
      end
    end
  end
end

Dependabot::Utils.register_version_class("hex", Dependabot::Hex::Version)
