# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/gradle/version"

module Dependabot
  module Gradle
    class Requirement < Gem::Requirement
      quoted = OPS.keys.map { |k| Regexp.quote k }.join("|")
      PATTERN_RAW =
        "\\s*(#{quoted})?\\s*(#{Gradle::Version::VERSION_PATTERN})\\s*"
      PATTERN = /\A#{PATTERN_RAW}\z/.freeze

      def self.parse(obj)
        return ["=", Gradle::Version.new(obj.to_s)] if obj.is_a?(Gem::Version)

        unless (matches = PATTERN.match(obj.to_s))
          msg = "Illformed requirement [#{obj.inspect}]"
          raise BadRequirementError, msg
        end

        return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"

        [matches[1] || "=", Gradle::Version.new(matches[2])]
      end

      def self.requirements_array(requirement_string)
        split_java_requirement(requirement_string).map do |str|
          new(str)
        end
      end

      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          convert_java_constraint_to_ruby_constraint(req_string)
        end

        super(requirements)
      end

      def satisfied_by?(version)
        version = Gradle::Version.new(version.to_s)
        super
      end

      private

      def self.split_java_requirement(req_string)
        req_string.split(/(?<=\]|\)),/).flat_map do |str|
          next str if str.start_with?("(", "[")

          exacts, *rest = str.split(/,(?=\[|\()/)
          [*exacts.split(","), *rest]
        end
      end
      private_class_method :split_java_requirement

      def convert_java_constraint_to_ruby_constraint(req_string)
        return unless req_string

        if self.class.send(:split_java_requirement, req_string).count > 1
          raise "Can't convert multiple Java reqs to a single Ruby one"
        end

        if req_string&.include?(",")
          return convert_java_range_to_ruby_range(req_string)
        end

        convert_java_equals_req_to_ruby(req_string)
      end

      def convert_java_range_to_ruby_range(req_string)
        lower_b, upper_b = req_string.split(",").map(&:strip)

        lower_b =
          if ["(", "["].include?(lower_b) then nil
          elsif lower_b.start_with?("(") then "> #{lower_b.sub(/\(\s*/, '')}"
          else ">= #{lower_b.sub(/\[\s*/, '').strip}"
          end

        upper_b =
          if [")", "]"].include?(upper_b) then nil
          elsif upper_b.end_with?(")") then "< #{upper_b.sub(/\s*\)/, '')}"
          else "<= #{upper_b.sub(/\s*\]/, '').strip}"
          end

        [lower_b, upper_b].compact
      end

      def convert_java_equals_req_to_ruby(req_string)
        return convert_wildcard_req(req_string) if req_string&.include?("+")

        # If a soft requirement is being used, treat it as an equality matcher
        return req_string unless req_string&.start_with?("[")

        req_string.gsub(/[\[\]\(\)]/, "")
      end

      def convert_wildcard_req(req_string)
        version = req_string.split("+").first
        return ">= 0" if version.nil? || version.empty?

        version += "0" if version.end_with?(".")
        "~> #{version}"
      end
    end
  end
end

Dependabot::Utils.
  register_requirement_class("gradle", Dependabot::Gradle::Requirement)
