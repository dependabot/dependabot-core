# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"

module Dependabot
  module Composer
    class Requirement < Dependabot::Requirement
      extend T::Sig

      AND_SEPARATOR = /(?<=[a-zA-Z0-9*])(?<!\sas)[\s,]+(?![\s,]*[|-]|as)/
      OR_SEPARATOR = /(?<=[a-zA-Z0-9*])[\s,]*\|\|?\s*/

      sig { params(obj: String).returns(T::Array[T.any(String, Version)]) }
      def self.parse(obj)
        new_obj = obj.gsub(/@\w+/, "").gsub(/[a-z0-9\-_\.]*\sas\s+/i, "")
        return DefaultRequirement if new_obj == ""

        super(new_obj)
      end

      # Returns an array of requirements. At least one requirement from the
      # returned array must be satisfied for a version to be valid.
      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        T.must(requirement_string).strip.split(OR_SEPARATOR).map do |req_string|
          new(req_string)
        end
      end

      sig { params(requirements: T.untyped).void }
      def initialize(*requirements)
        requirements =
          requirements.flatten
                      .flat_map { |req_string| req_string.split(AND_SEPARATOR) }
                      .flat_map { |req| convert_php_constraint_to_ruby_constraint(req) }

        super(requirements)
      end

      private

      sig { params(req_string: String).returns(T.any(String, T::Array[String])) }
      def convert_php_constraint_to_ruby_constraint(req_string)
        req_string = req_string.strip.gsub(/v(?=\d)/, "").gsub(/\.$/, "")

        # Return an unlikely version if a dev requirement is specified. This
        # ensures that the dev-requirement doesn't match anything.
        return "0-dev-branch-match" if req_string.strip.start_with?("dev-")

        if req_string.start_with?("*", "x") then ">= 0"
        elsif req_string.include?("*") then convert_wildcard_req(req_string)
        elsif req_string.start_with?("^") then convert_caret_req(req_string)
        elsif req_string.match?(/^~[^>]/) then convert_tilde_req(req_string)
        elsif req_string.include?(".x") then convert_wildcard_req(req_string)
        elsif req_string.match?(/\s-\s/) then convert_hyphen_req(req_string)
        else
          req_string
        end
      end

      sig { params(req_string: String).returns(String) }
      def convert_wildcard_req(req_string)
        if req_string.start_with?(">", "<")
          msg = "Illformed requirement [#{req_string.inspect}]"
          raise Gem::Requirement::BadRequirementError, msg
        end

        version = req_string.gsub(/^~/, "").gsub(/(?:\.|^)[\*x]/, "")
        "~> #{version}.0"
      end

      sig { params(req_string: String).returns(String) }
      def convert_tilde_req(req_string)
        version = req_string.gsub(/^~/, "")
        "~> #{version}"
      end

      sig { params(req_string: String).returns(T::Array[String]) }
      def convert_caret_req(req_string)
        version = req_string.gsub(/^\^/, "").gsub("x-dev", "0")
        parts = version.split(".")
        first_non_zero = parts.find { |d| d != "0" }
        first_non_zero_index =
          first_non_zero ? T.must(parts.index(first_non_zero)) : parts.count - 1
        upper_bound = parts.map.with_index do |part, i|
          if i < first_non_zero_index then part
          elsif i == first_non_zero_index then (part.to_i + 1).to_s
          else
            0
          end
        end.join(".")

        [">= #{version}", "< #{upper_bound}"]
      end

      sig { params(req_string: String).returns(T::Array[String]) }
      def convert_hyphen_req(req_string)
        lower_bound, upper_bound = req_string.split(/\s+-\s+/)
        upper_bound = T.must(upper_bound)
        if upper_bound.split(".").count < 3
          upper_bound_parts = upper_bound.split(".")
          upper_bound_parts[-1] = (upper_bound_parts[-1].to_i + 1).to_s
          upper_bound = upper_bound_parts.join(".")

          [">= #{lower_bound}", "< #{upper_bound}"]
        else
          [">= #{lower_bound}", "<= #{upper_bound}"]
        end
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("composer", Dependabot::Composer::Requirement)
