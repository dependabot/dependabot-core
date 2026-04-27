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
          pattern = self.class.const_get(:PATTERN)
          ruby_style_pattern = self.class.const_get(:RUBY_STYLE_PATTERN)

          if version_reqs.length > 1 && !version_reqs.all? { |s| pattern.match?(s) }
            return convert_java_range_to_ruby_range(req_string)
          end

          version_reqs.map do |r|
            # if an operator is already provided, use it
            next r if r.match?(ruby_style_pattern)

            convert_java_equals_req_to_ruby(r)
          end
        end

        sig { params(req_string: String).returns(T::Array[T.nilable(String)]) }
        def convert_java_range_to_ruby_range(req_string)
          parts = req_string.split(",").map(&:strip)
          lower_b = T.let(parts[0], T.nilable(String))
          upper_b = T.let(parts[1], T.nilable(String))

          lower_b =
            if lower_b && ["(", "["].include?(lower_b) then nil
            elsif lower_b&.start_with?("(") then "> #{lower_b.sub(/\(\s*/, '')}"
            elsif lower_b
              ">= #{lower_b.sub(/\[\s*/, '').strip}"
            end

          upper_b =
            if upper_b && [")", "]"].include?(upper_b) then nil
            elsif upper_b&.end_with?(")") then "< #{upper_b.sub(/\s*\)/, '')}"
            elsif upper_b
              "<= #{upper_b.sub(/\s*\]/, '').strip}"
            end

          [lower_b, upper_b].compact
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
