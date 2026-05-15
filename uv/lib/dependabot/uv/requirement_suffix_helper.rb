# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Uv
    module RequirementSuffixHelper
      extend T::Sig

      REQUIREMENT_SUFFIX_REGEX = T.let(
        Regexp.new(
          "\\A(?<requirement>.*?)(?<suffix>\\s*(?:;|#).*)?\\z",
          Regexp::MULTILINE
        ).freeze,
        Regexp
      )

      sig { params(segment: String).returns(T::Array[String]) }
      def self.split(segment)
        match = REQUIREMENT_SUFFIX_REGEX.match(segment)
        requirement = match ? match[:requirement] : segment
        suffix = match&.[](:suffix) || ""

        [T.must(requirement).strip, suffix]
      end
    end
  end
end
