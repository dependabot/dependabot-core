# typed: strict
# frozen_string_literal: true

# For details on pub version constraints see:
# https://github.com/dart-lang/pub_semver

###################################################################

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/pub/version"

module Dependabot
  module Pub
    class Requirement < Dependabot::Requirement
      extend T::Sig

      quoted = OPS.keys.map { |k| Regexp.quote(k) }.join("|")
      version_pattern = Pub::Version::VERSION_PATTERN

      PATTERN_RAW = T.let("\\s*(#{quoted})?\\s*(#{version_pattern})\\s*".freeze, String)
      PATTERN = /\A#{PATTERN_RAW}\z/

      # Use Pub::Version rather than Gem::Version to ensure that
      # pre-release versions aren't transformed.
      sig do
        params(
          obj: T.any(String, Gem::Version, Pub::Version)
        ).returns(T::Array[T.any(String, Pub::Version)])
      end
      def self.parse(obj)
        return ["=", Pub::Version.new(obj.to_s)] if obj.is_a?(Gem::Version)

        unless (matches = PATTERN.match(obj.to_s))
          msg = "Illformed requirement [#{obj.inspect}]"
          raise BadRequirementError, msg
        end

        return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"

        [matches[1] || "=", Pub::Version.new(T.must(matches[2]))]
      end

      # For consistency with other languages, we define a requirements array.
      # Dart doesn't have an `OR` separator for requirements, so it always
      # contains a single element.
      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        [new(T.must(requirement_string))]
      end

      sig { params(requirements: T.any(String, T::Array[String]), raw_constraint: T.nilable(String)).void }
      def initialize(*requirements, raw_constraint: nil)
        requirements = requirements.flatten.flat_map do |req_string|
          req_string.split(",").map(&:strip).map do |r|
            convert_dart_constraint_to_ruby_constraint(r.strip)
          end
        end
        super(requirements)

        @raw_constraint = raw_constraint
      end

      sig { returns(String) }
      def to_s
        if @raw_constraint.nil?
          as_list.join " "
        else
          @raw_constraint
        end
      end

      private

      sig { params(req_string: String).returns(T.any(String, T::Array[T.nilable(String)])) }
      def convert_dart_constraint_to_ruby_constraint(req_string)
        if req_string.empty? || req_string == "any" then ">= 0"
        elsif req_string.match?(/^~[^>]/) then convert_tilde_req(req_string)
        elsif req_string.match?(/^\^/) then convert_caret_req(req_string)
        elsif req_string.match?(/[<=>]/) then convert_range_req(req_string)
        else
          ruby_range(req_string)
        end
      end

      sig { params(req_string: String).returns(String) }
      def convert_tilde_req(req_string)
        version = req_string.gsub(/^~/, "")
        parts = version.split(".")
        "~> #{parts.join('.')}"
      end

      sig { params(req_string: String).returns(T::Array[T.nilable(String)]) }
      def convert_range_req(req_string)
        req_string.scan(
          /((?:>|<|=|<=|>=)\s*#{Pub::Version::VERSION_PATTERN})\s*/o
        ).map { |x| x[0]&.strip }
      end

      sig { params(req_string: String).returns(String) }
      def ruby_range(req_string)
        parts = req_string.split(".")

        # If we have three or more parts then this is an exact match
        return req_string if parts.count >= 3

        # If we have no parts then the version is completely unlocked
        return ">= 0" if parts.count.zero?

        # If we have fewer than three parts we do a partial match
        parts << "0"
        "~> #{parts.join('.')}"
      end

      sig { params(req_string: String).returns(T::Array[String]) }
      def convert_caret_req(req_string)
        # Copied from Cargo::Requirement which allows less than 3 components
        # so we could be more strict in the parsing here.
        version = req_string.gsub(/^\^/, "")
        parts = version.split(".")
        first_non_zero = parts.find { |d| d != "0" }
        first_non_zero_index =
          first_non_zero ? parts.index(first_non_zero) : parts.count - 1
        upper_bound = parts.map.with_index do |part, i|
          if i < T.must(first_non_zero_index) then part
          elsif i == first_non_zero_index then (part.to_i + 1).to_s
          else
            0
          end
        end.join(".")

        [">= #{version}", "< #{upper_bound}"]
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("pub", Dependabot::Pub::Requirement)
