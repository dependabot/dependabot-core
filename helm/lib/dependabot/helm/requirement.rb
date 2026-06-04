# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/helm/version"

module Dependabot
  module Helm
    # Parses Helm Chart.yaml SemVer range constraints (^, ~, x-ranges, hyphen
    # ranges, || OR, space-AND and comma-AND). Adapted from
    # Dependabot::NpmAndYarn::Requirement: Helm uses the same SemVer family
    # (Masterminds), unlike the Gem-style Docker::Requirement registered for the
    # docker-image path.
    #
    # NOTE: this class is intentionally NOT registered as the requirement class
    # for "helm" (that remains Docker::Requirement, used by the docker-image
    # path and ignore conditions). It is used explicitly by the range-preserving
    # requirements updater.
    class Requirement < Dependabot::Requirement
      extend T::Sig

      AND_SEPARATOR = T.let(/(?<=[a-zA-Z0-9*])\s+(?:&+\s+)?(?!\s*[|-])/, Regexp)
      OR_SEPARATOR = T.let(/(?<=[a-zA-Z0-9*])\s*\|+/, Regexp)

      # Allow an optional 'v' prefix on versions.
      quoted = OPS.keys.map { |k| Regexp.quote(k) }.join("|")
      version_pattern = "v?#{Gem::Version::VERSION_PATTERN}"

      PATTERN_RAW = T.let("\\s*(#{quoted})?\\s*(#{version_pattern})\\s*".freeze, String)
      PATTERN = T.let(/\A#{PATTERN_RAW}\z/, Regexp)

      # Always returns a Helm::Version (never the plain Gem::Version-backed
      # DefaultRequirement), so satisfaction comparisons stay Helm::Version vs
      # Helm::Version — Helm::Version#<=> has a strict sig that rejects plain
      # Gem::Version operands.
      sig do
        params(obj: T.any(String, Gem::Version))
          .returns(T::Array[T.any(String, Helm::Version)])
      end
      def self.parse(obj)
        return ["=", Helm::Version.new(obj.to_s)] if obj.is_a?(Gem::Version)

        unless (matches = PATTERN.match(obj.to_s))
          raise BadRequirementError, "Illformed requirement [#{obj.inspect}]"
        end

        [matches[1] || "=", Helm::Version.new(T.must(matches[2]))]
      end

      # Returns an array of requirements. At least one requirement from the
      # returned array must be satisfied for a version to be valid.
      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        return [new(nil)] if requirement_string.nil?

        # Parentheses are extremely rare in Helm constraints; strip them.
        requirement_string = requirement_string.gsub(/[()]/, "")
        requirement_string.strip.split(OR_SEPARATOR).map do |req_string|
          new(req_string.strip.split(AND_SEPARATOR))
        end
      end

      sig { params(requirements: T.nilable(T.any(String, T::Array[String]))).void }
      def initialize(*requirements)
        requirements = requirements.flatten
                                   .flat_map { |req_string| T.must(req_string).split(",").map(&:strip) }
                                   .flat_map { |req_string| convert_helm_constraint_to_ruby_constraint(req_string) }

        super
      end

      private

      sig { params(req_string: String).returns(T.any(String, T::Array[String])) }
      def convert_helm_constraint_to_ruby_constraint(req_string)
        # Leave dist-tags / non-numeric leading tokens untouched.
        return req_string if req_string.match?(/^([A-Za-uw-z]|v[^\d])/)

        req_string = req_string.gsub(/(?:\.|^)[xX*]/, "")

        if req_string.empty? then ">= 0"
        elsif req_string.start_with?("~>") then req_string
        elsif req_string.start_with?("=") then req_string.gsub(/^=*/, "")
        elsif req_string.start_with?("~") then convert_tilde_req(req_string)
        elsif req_string.start_with?("^") then convert_caret_req(req_string)
        elsif req_string.include?(" - ") then convert_hyphen_req(req_string)
        elsif req_string.match?(/[<>]/) then req_string
        else ruby_range(req_string)
        end
      end

      sig { params(req_string: String).returns(String) }
      def convert_tilde_req(req_string)
        version = req_string.gsub(/^~\>?[\s=]*/, "")
        parts = version.split(".")
        parts << "0" if parts.count < 3
        "~> #{parts.join('.')}"
      end

      sig { params(req_string: String).returns(T::Array[String]) }
      def convert_hyphen_req(req_string)
        parts = req_string.split(/\s+-\s+/)
        lower_bound = T.must(parts[0])
        upper_bound = T.must(parts[1])
        lower_bound_parts = lower_bound.split(".")
        lower_bound_parts.fill("0", lower_bound_parts.length...3)

        upper_bound_parts = upper_bound.split(".")
        upper_bound_range =
          if upper_bound_parts.length < 3
            # When upper bound is a partial version treat these as an X-range
            upper_bound_parts[-1] = upper_bound_parts[-1].to_i + 1 if upper_bound_parts[-1].to_i.positive?
            upper_bound_parts.fill("0", upper_bound_parts.length...3)
            "< #{upper_bound_parts.join('.')}.a"
          else
            "<= #{upper_bound_parts.join('.')}"
          end

        [">= #{lower_bound_parts.join('.')}", upper_bound_range]
      end

      sig { params(req_string: String).returns(String) }
      def ruby_range(req_string)
        parts = req_string.split(".")
        # If we have three or more parts then this is an exact match
        return req_string if parts.count >= 3

        # If we have fewer than three parts we do a partial match
        parts << "0"
        "~> #{parts.join('.')}"
      end

      sig { params(req_string: String).returns(T::Array[String]) }
      def convert_caret_req(req_string)
        version = req_string.gsub(/^\^[\s=]*/, "")
        parts = version.split(".")
        parts.fill("x", parts.length...3)
        first_non_zero = parts.find { |d| d != "0" }
        first_non_zero_index =
          first_non_zero ? T.must(parts.index(first_non_zero)) : parts.count - 1
        # If the requirement has a blank minor or patch version increment the
        # previous index value with 1
        first_non_zero_index -= 1 if first_non_zero == "x"
        upper_bound = parts.map.with_index do |part, i|
          if i < first_non_zero_index then part
          elsif i == first_non_zero_index then (part.to_i + 1).to_s
          elsif i > first_non_zero_index && i == 2 then "0.a"
          else 0
          end
        end.join(".")

        [">= #{version}", "< #{upper_bound}"]
      end
    end
  end
end
