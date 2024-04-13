# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/maven/requirement"
require "dependabot/gradle/version"

module Dependabot
  module Gradle
    class Requirement < Dependabot::Requirement
      extend T::Sig

      quoted = OPS.keys.map { |k| Regexp.quote k }.join("|")
      PATTERN_RAW = T.let("\\s*(#{quoted})?\\s*(#{Gradle::Version::VERSION_PATTERN})\\s*".freeze, String)
      PATTERN = /\A#{PATTERN_RAW}\z/

      sig { override.params(obj: T.any(Gem::Version, String)).returns([String, Gem::Version]) }
      def self.parse(obj)
        return ["=", Gradle::Version.new(obj.to_s)] if obj.is_a?(Gem::Version)

        unless (matches = PATTERN.match(obj.to_s))
          msg = "Illformed requirement [#{obj.inspect}]"
          raise BadRequirementError, msg
        end

        return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"

        [matches[1] || "=", Gradle::Version.new(T.must(matches[2]))]
      end

      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        split_java_requirement(requirement_string).map do |str|
          new(str)
        end
      end

      sig { params(requirements: T.any(T.nilable(String), T::Array[T.nilable(String)])).void }
      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          convert_java_constraint_to_ruby_constraint(req_string)
        end

        super(requirements)
      end

      sig { override.params(version: Gem::Version).returns(T::Boolean) }
      def satisfied_by?(version)
        version = Gradle::Version.new(version.to_s)
        super
      end

      private

      sig { params(req_string: T.nilable(String)).returns(T::Array[T.nilable(String)]) }
      def self.split_java_requirement(req_string)
        return [req_string] unless req_string&.match?(Maven::Requirement::OR_SYNTAX)

        req_string.split(Maven::Requirement::OR_SYNTAX).flat_map do |str|
          next str if str.start_with?("(", "[")

          exacts, *rest = str.split(/,(?=\[|\()/)
          [*T.must(exacts).split(","), *rest]
        end
      end
      private_class_method :split_java_requirement

      sig { params(req_string: T.nilable(String)).returns(T.nilable(T::Array[String])) }
      def convert_java_constraint_to_ruby_constraint(req_string)
        return unless req_string

        if self.class.send(:split_java_requirement, req_string).count > 1
          raise "Can't convert multiple Java reqs to a single Ruby one"
        end

        # NOTE: Support ruby-style version requirements that are created from
        # PR ignore conditions
        version_reqs = req_string.split(",").map(&:strip)
        if req_string.include?(",") && !version_reqs.all? { |s| PATTERN.match?(s) }
          convert_java_range_to_ruby_range(req_string) if req_string.include?(",")
        else
          version_reqs.map { |r| convert_java_equals_req_to_ruby(r) }
        end
      end

      sig { params(req_string: String).returns(T::Array[String]) }
      def convert_java_range_to_ruby_range(req_string)
        lower_b, upper_b = req_string.split(",").map(&:strip)

        lower_b =
          if ["(", "["].include?(lower_b) then nil
          elsif T.must(lower_b).start_with?("(") then "> #{T.must(lower_b).sub(/\(\s*/, '')}"
          else
            ">= #{T.must(lower_b).sub(/\[\s*/, '').strip}"
          end

        upper_b =
          if [")", "]"].include?(upper_b) then nil
          elsif T.must(upper_b).end_with?(")") then "< #{T.must(upper_b).sub(/\s*\)/, '')}"
          else
            "<= #{T.must(upper_b).sub(/\s*\]/, '').strip}"
          end

        [lower_b, upper_b].compact
      end

      sig { params(req_string: String).returns(String) }
      def convert_java_equals_req_to_ruby(req_string)
        return convert_wildcard_req(req_string) if req_string.include?("+")

        # If a soft requirement is being used, treat it as an equality matcher
        return req_string unless req_string.start_with?("[")

        req_string.gsub(/[\[\]\(\)]/, "")
      end

      sig { params(req_string: String).returns(String) }
      def convert_wildcard_req(req_string)
        version = req_string.split("+").first
        return ">= 0" if version.nil? || version.empty?

        version += "0" if version.end_with?(".")
        "~> #{version}"
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("gradle", Dependabot::Gradle::Requirement)
