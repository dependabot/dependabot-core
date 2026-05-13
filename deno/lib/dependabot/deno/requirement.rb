# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/deno/version"

# Deno uses npm-style semver constraints for both jsr: and npm: specifiers.
# Supported operators: ^, ~, >=, >, <=, <, =, exact version

module Dependabot
  module Deno
    class Requirement < Dependabot::Requirement
      extend T::Sig

      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        return [new(nil)] if requirement_string.nil?

        [new(requirement_string)]
      end

      sig { params(requirements: T.nilable(T.any(String, T::Array[String]))).void }
      def initialize(*requirements)
        requirements = requirements.flatten.compact.flat_map do |req_string|
          req_string.split(",").map(&:strip).map do |r|
            convert_deno_constraint_to_ruby_constraint(r.strip)
          end
        end
        requirements = [">= 0"] if requirements.empty?
        super(requirements)
      end

      private

      sig { params(req_string: String).returns(T.any(String, T::Array[String])) }
      def convert_deno_constraint_to_ruby_constraint(req_string)
        if req_string.match?(/^\^/) then convert_caret_req(req_string)
        elsif req_string.match?(/^~[^>]/) then convert_tilde_req(req_string)
        elsif req_string.match?(/[<=>]/) then req_string
        else
          "= #{req_string}"
        end
      end

      sig { params(req_string: String).returns(String) }
      def convert_tilde_req(req_string)
        version = req_string.gsub(/^~/, "")
        "~> #{version}"
      end

      sig { params(req_string: String).returns(T::Array[String]) }
      def convert_caret_req(req_string)
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

Dependabot::Utils.register_requirement_class("deno", Dependabot::Deno::Requirement)
