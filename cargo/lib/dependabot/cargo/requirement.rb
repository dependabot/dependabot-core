# typed: true
# frozen_string_literal: true

################################################################################
# For more details on rust version constraints, see:                           #
# - https://doc.rust-lang.org/cargo/reference/specifying-dependencies.html     #
# - https://steveklabnik.github.io/semver/semver/index.html                    #
################################################################################

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/cargo/version"

module Dependabot
  module Cargo
    class Requirement < Dependabot::Requirement
      extend T::Sig

      quoted = OPS.keys.map { |k| Regexp.quote(k) }.join("|")
      version_pattern = Cargo::Version::VERSION_PATTERN

      PATTERN_RAW = "\\s*(#{quoted})?\\s*(#{version_pattern})\\s*".freeze
      PATTERN = /\A#{PATTERN_RAW}\z/

      # Use Cargo::Version rather than Gem::Version to ensure that
      # pre-release versions aren't transformed.
      def self.parse(obj)
        return ["=", Cargo::Version.new(obj.to_s)] if obj.is_a?(Gem::Version)

        unless (matches = PATTERN.match(obj.to_s))
          msg = "Illformed requirement [#{obj.inspect}]"
          raise BadRequirementError, msg
        end

        return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"

        [matches[1] || "=", Cargo::Version.new(T.must(matches[2]))]
      end

      # For consistency with other languages, we define a requirements array.
      # Rust doesn't have an `OR` separator for requirements, so it always
      # contains a single element.
      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          req_string.split(",").map(&:strip).map do |r|
            convert_rust_constraint_to_ruby_constraint(r.strip)
          end
        end

        super(requirements)
      end

      private

      def convert_rust_constraint_to_ruby_constraint(req_string)
        if req_string.include?("*")
          ruby_range(req_string.gsub(/(?:\.|^)[*]/, "").gsub(/^[^\d]/, ""))
        elsif req_string.match?(/^~[^>]/) then convert_tilde_req(req_string)
        elsif req_string.match?(/^[\d^]/) then convert_caret_req(req_string)
        elsif req_string.match?(/[<=>]/) then req_string
        else
          ruby_range(req_string)
        end
      end

      def convert_tilde_req(req_string)
        version = req_string.gsub(/^~/, "")
        parts = version.split(".")
        parts << "0" if parts.count < 3
        "~> #{parts.join('.')}"
      end

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

      def convert_caret_req(req_string)
        version = req_string.gsub(/^\^/, "")
        parts = version.split(".")
        first_non_zero = parts.find { |d| d != "0" }
        first_non_zero_index =
          first_non_zero ? parts.index(first_non_zero) : parts.count - 1
        upper_bound = parts.map.with_index do |part, i|
          if i < first_non_zero_index then part
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
  .register_requirement_class("cargo", Dependabot::Cargo::Requirement)
