# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/version"

module Dependabot
  class Version
    # Standard SemVer §11 pre-release precedence comparison.
    # Include in ecosystem Version classes that need correct ordering
    # of pre-release identifiers (e.g. 1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0).
    module SemverPrereleaseComparison
      extend T::Sig

      sig { params(left: T.nilable(String), right: T.nilable(String)).returns(Integer) }
      def compare_semver_prerelease(left, right)
        return 0 if left.nil? && right.nil?
        return 1 if left.nil?
        return -1 if right.nil?

        left_ids = left.split(".")
        right_ids = right.split(".")

        left_ids.zip(right_ids).each do |l, r|
          return -1 if l.nil?
          return 1 if r.nil?

          cmp = compare_semver_identifier(l, r)
          return cmp unless cmp.zero?
        end

        left_ids.length <=> right_ids.length
      end

      private

      sig { params(left: String, right: String).returns(Integer) }
      def compare_semver_identifier(left, right)
        left_numeric = left.match?(/\A\d+\z/)
        right_numeric = right.match?(/\A\d+\z/)

        if left_numeric && right_numeric
          left.to_i <=> right.to_i
        elsif left_numeric
          -1
        elsif right_numeric
          1
        else
          T.must(left <=> right)
        end
      end
    end
  end
end
