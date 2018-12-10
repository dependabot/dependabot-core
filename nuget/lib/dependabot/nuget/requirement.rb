# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/nuget/version"

# For details on .NET version constraints see:
# https://docs.microsoft.com/en-us/nuget/reference/package-versioning
module Dependabot
  module Nuget
    class Requirement < Gem::Requirement
      def self.parse(obj)
        if obj.is_a?(Gem::Version)
          return ["=", Nuget::Version.new(obj.to_s)]
        end

        unless (matches = PATTERN.match(obj.to_s))
          msg = "Illformed requirement [#{obj.inspect}]"
          raise BadRequirementError, msg
        end

        return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"

        [matches[1] || "=", Nuget::Version.new(matches[2])]
      end

      # For consistency with other langauges, we define a requirements array.
      # Dotnet doesn't have an `OR` separator for requirements, so it always
      # contains a single element.
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          convert_dotnet_constraint_to_ruby_constraint(req_string)
        end

        super(requirements)
      end

      def satisfied_by?(version)
        version = Nuget::Version.new(version.to_s)
        super
      end

      private

      def convert_dotnet_constraint_to_ruby_constraint(req_string)
        return unless req_string

        if req_string&.start_with?("(", "[")
          return convert_dotnet_range_to_ruby_range(req_string)
        end

        return req_string.split(",").map(&:strip) if req_string.include?(",")
        return req_string unless req_string.include?("*")

        convert_wildcard_req(req_string)
      end

      def convert_dotnet_range_to_ruby_range(req_string)
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

      def convert_wildcard_req(req_string)
        return ">= 0" if req_string.start_with?("*")

        defined_part = req_string.split("*").first
        suffix = defined_part.end_with?(".") ? "0" : "a"
        version = defined_part + suffix
        "~> #{version}"
      end
    end
  end
end

Dependabot::Utils.
  register_requirement_class("nuget", Dependabot::Nuget::Requirement)
