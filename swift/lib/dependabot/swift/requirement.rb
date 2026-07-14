# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/swift/version"

module Dependabot
  module Swift
    class Requirement < Dependabot::Requirement
      extend T::Sig

      quoted = OPS.keys.map { |k| Regexp.quote(k) }.join("|")
      # Swift requirement grammar (intentionally not strict SemVer): allows multi-segment numeric
      # cores like "4.2.5.1"/"3.0.0.0" for compatibility bounds.
      num = "(?:0|[1-9][0-9]*)"
      pre_id = "(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
      version_pattern = "#{num}(?:\\.#{num})*" \
                        "(?:-#{pre_id}(?:\\.#{pre_id})*)?" \
                        '(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?'

      PATTERN = T.let(/\A\s*(#{quoted})?\s*(#{version_pattern})\s*\z/, Regexp)

      # Parse each boundary into a Swift::Version so prerelease boundaries use SemVer section 11 ordering.
      sig { override.params(obj: T.any(Gem::Version, String)).returns([String, Gem::Version]) }
      def self.parse(obj)
        # Preserve an existing version object; reconstructing from #to_s would be lossy.
        return ["=", obj] if obj.is_a?(Gem::Version)

        unless (matches = PATTERN.match(obj.to_s))
          raise BadRequirementError, "Illformed requirement [#{obj.inspect}]"
        end

        return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"

        [matches[1] || "=", Swift::Version.new(T.must(matches[2]))]
      end

      # For consistency with other languages, we define a requirements array.
      # Swift doesn't have an `OR` separator for requirements, so it
      # always contains a single element.
      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        [new(T.must(requirement_string))]
      end

      # Patches Gem::Requirement to make it accept requirement strings like
      # "~> 4.2.5, >= 4.2.5.1" without first needing to split them.
      sig { params(requirements: T.any(String, T::Array[String])).void }
      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          req_string.split(",").map(&:strip)
        end

        super(requirements)
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("swift", Dependabot::Swift::Requirement)
