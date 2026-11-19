# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/apm/version"
require "dependabot/requirement"
require "dependabot/utils"

module Dependabot
  module Apm
    class Requirement < Dependabot::Requirement
      extend T::Sig

      # Requirement bounds are matched with SemVer 2.0.0 precedence, to stay
      # consistent with Apm::Version. Left to Gem::Requirement, a prerelease
      # bound such as `1.0.0-alpha.beta` is rewritten to the RubyGems form
      # `1.0.0.pre.alpha.beta` and compared with RubyGems precedence, which
      # orders prerelease identifiers the opposite way to SemVer (so a range
      # like `< 1.0.0-alpha.beta` would wrongly exclude `1.0.0-alpha.1`).
      quoted = OPS.keys.map { |k| Regexp.quote(k) }.join("|")
      # Gem::Version::VERSION_PATTERN covers the release and `-prerelease`
      # portions; the trailing group additionally accepts SemVer `+build`
      # metadata so bounds like `= 1.0.0+build.5` are recognised too.
      version_pattern = "#{Gem::Version::VERSION_PATTERN}(?:\\+[0-9A-Za-z][0-9A-Za-z.-]*)?"

      PATTERN_RAW = T.let("\\s*(#{quoted})?\\s*(#{version_pattern})\\s*".freeze, String)
      PATTERN = /\A#{PATTERN_RAW}\z/

      # Builds each requirement bound from an Apm::Version so prerelease
      # ordering follows SemVer. Operands that are not strict SemVer (e.g. the
      # partial `>= 1.0` or `>= 0`) fall back to RubyGems parsing, which does
      # not have the prerelease-ordering problem.
      sig { override.params(obj: T.any(Gem::Version, String)).returns([String, Gem::Version]) }
      def self.parse(obj)
        if obj.is_a?(String) && (matches = PATTERN.match(obj)) && Apm::Version.correct?(T.must(matches[2]))
          return [matches[1] || "=", Apm::Version.new(T.must(matches[2]))]
        end

        super
      end

      # For consistency with other languages, we define a requirements array.
      # APM doesn't have an `OR` separator for requirements, so it always
      # contains a single element.
      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      # Patches Gem::Requirement to make it accept requirement strings like
      # "~> 4.2.5, >= 4.2.5.1" without first needing to split them.
      sig { params(requirements: T.any(T.nilable(String), T::Array[T.nilable(String)])).void }
      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          req_string&.split(",")&.map(&:strip)
        end

        super(requirements)
      end
    end
  end
end

Dependabot::Utils.register_requirement_class(
  "apm",
  Dependabot::Apm::Requirement
)
