# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/requirement"

module Dependabot
  module Maven
    module Shared
      class SharedRequirement < Dependabot::Requirement
        extend T::Sig
        extend T::Helpers

        abstract!

        OR_SYNTAX = T.let(/(?<=\]|\)),/, Regexp)

        sig { abstract.returns(Regexp) }
        def self.pattern; end

        sig { abstract.returns(Regexp) }
        def self.ruby_style_pattern; end

        sig { params(requirements: T.untyped).void }
        def initialize(*requirements)
          requirements = requirements.flatten.flat_map do |req_string|
            convert_java_constraint_to_ruby_constraint(req_string)
          end

          super(requirements)
        end

        private

        sig { params(req_string: T.nilable(String)).returns(T::Array[String]) }
        def self.split_java_requirement(req_string)
          return [req_string || ""] unless req_string&.match?(OR_SYNTAX)

          req_string.split(OR_SYNTAX).flat_map do |str|
            next str if str.start_with?("(", "[")

            exacts, *rest = str.split(/,(?=\[|\()/)
            [*T.must(exacts).split(","), *rest]
          end
        end
        private_class_method :split_java_requirement

        sig do
          params(
            req_string: T.nilable(String)
          )
            .returns(T.nilable(T.any(T::Array[String], T::Array[T.nilable(String)])))
        end
        def convert_java_constraint_to_ruby_constraint(req_string)
          return unless req_string

          if self.class.send(:split_java_requirement, req_string).count > 1
            raise "Can't convert multiple Java reqs to a single Ruby one"
          end

          version_reqs = req_string.split(",").map(&:strip)

          if version_reqs.length > 1 && !version_reqs.all? { |s| self.class.pattern.match?(s) }
            return convert_java_range_to_ruby_range(req_string)
          end

          version_reqs.map do |r|
            # if an operator is already provided, use it
            next r if r.match?(self.class.ruby_style_pattern)

            convert_java_equals_req_to_ruby(r)
          end
        end

        sig { params(req_string: String).returns(T::Array[T.nilable(String)]) }
        def convert_java_range_to_ruby_range(req_string)
          parts = req_string.split(",").map(&:strip)
          lower_b = parse_lower_bound(parts[0])
          upper_b = parse_upper_bound(parts[1])
          [lower_b, upper_b].compact
        end

        sig { params(bound: T.nilable(String)).returns(T.nilable(String)) }
        def parse_lower_bound(bound)
          return nil if bound.nil? || ["(", "["].include?(bound)
          return "> #{bound.sub(/\(\s*/, '')}" if bound.start_with?("(")

          ">= #{bound.sub(/\[\s*/, '').strip}"
        end

        sig { params(bound: T.nilable(String)).returns(T.nilable(String)) }
        def parse_upper_bound(bound)
          return nil if bound.nil? || [")", "]"].include?(bound)
          return "< #{bound.sub(/\s*\)/, '')}" if bound.end_with?(")")

          "<= #{bound.sub(/\s*\]/, '').strip}"
        end

        sig { params(req_string: T.nilable(String)).returns(T.nilable(String)) }
        def convert_java_equals_req_to_ruby(req_string)
          return convert_wildcard_req(req_string) if req_string&.end_with?("+")

          # If a soft requirement is being used, treat it as an equality matcher
          return req_string unless req_string&.start_with?("[")

          req_string.gsub(/[\[\]\(\)]/, "")
        end

        sig { params(req_string: T.nilable(String)).returns(String) }
        def convert_wildcard_req(req_string)
          version = req_string&.split("+")&.first
          return ">= 0" if version.nil? || version.empty?

          version += "0" if version.end_with?(".")
          "~> #{version}"
        end
      end
    end
  end
end
