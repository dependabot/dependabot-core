# frozen_string_literal: true

require "rubygems_version_patch"
require "dependabot/utils"

# Elixir versions can include build information, which Ruby can't parse.
# This class augments Gem::Version with build information.
# See https://hexdocs.pm/elixir/Version.html for details.

module Dependabot
  module Hex
    class Version < Gem::Version
      attr_reader :build_info

      VERSION_PATTERN = Gem::Version::VERSION_PATTERN +
                        '(\+[0-9a-zA-Z\-.]+)?'

      def self.correct?(version)
        version = version.to_s.split("+").first if version.to_s.include?("+")
        super
      end

      def initialize(version)
        @version_string = version.to_s

        if version.to_s.include?("+")
          version, @build_info = version.to_s.split("+")
        end

        super
      end

      def to_s
        @version_string
      end

      def inspect # :nodoc:
        "#<#{self.class} #{@version_string}>"
      end

      def <=>(other)
        version_comparison = super(other)
        return version_comparison unless version_comparison.zero?

        return build_info.nil? ? 0 : 1 unless other.is_a?(Hex::Version)

        # Build information comparison
        lhsegments = build_info.to_s.split(".").map(&:downcase)
        rhsegments = other.build_info.to_s.split(".").map(&:downcase)
        limit = [lhsegments.count, rhsegments.count].min

        lhs = ["1", *lhsegments.first(limit)].join(".")
        rhs = ["1", *rhsegments.first(limit)].join(".")

        local_comparison = Gem::Version.new(lhs) <=> Gem::Version.new(rhs)

        return local_comparison unless local_comparison.zero?

        lhsegments.count <=> rhsegments.count
      end
    end
  end
end
