# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/nuget/version"

# For details on .NET version constraints see:
# https://docs.microsoft.com/en-us/nuget/reference/package-versioning
module Dependabot
  module Nuget
    class Requirement < Dependabot::Requirement
      extend T::Sig

      sig { override.params(obj: T.any(Gem::Version, String)).returns([String, Gem::Version]) }
      def self.parse(obj)
        return ["=", Nuget::Version.new(obj.to_s)] if obj.is_a?(Gem::Version)

        unless (matches = PATTERN.match(obj.to_s))
          msg = "Illformed requirement [#{obj.inspect}]"
          raise BadRequirementError, msg
        end

        return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"

        [matches[1] || "=", Nuget::Version.new(T.must(matches[2]))]
      end

      # For consistency with other languages, we define a requirements array.
      # Dotnet doesn't have an `OR` separator for requirements, so it always
      # contains a single element.
      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Dependabot::Requirement]) }
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      sig { params(requirements: T.any(T.nilable(String), T::Array[T.nilable(String)])).void }
      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          convert_dotnet_constraint_to_ruby_constraint(req_string)
        end

        requirements = requirements.compact.reject(&:empty?)

        super(requirements)
      end

      sig { override.params(version: Gem::Version).returns(T::Boolean) }
      def satisfied_by?(version)
        version = Nuget::Version.new(version.to_s)
        super
      end

      private

      sig { params(req_string: T.nilable(String)).returns(T.nilable(T.any(String, T::Array[String]))) }
      def convert_dotnet_constraint_to_ruby_constraint(req_string)
        return unless req_string

        return convert_dotnet_range_to_ruby_range(req_string) if req_string.start_with?("(", "[")

        return req_string.split(",").map(&:strip) if req_string.include?(",")

        return req_string unless req_string.include?("*")

        convert_wildcard_req(req_string)
      end

      # rubocop:disable Metrics/PerceivedComplexity
      sig { params(req_string: String).returns(T::Array[String]) }
      def convert_dotnet_range_to_ruby_range(req_string)
        lower_b, upper_b = req_string.split(",").map(&:strip).map do |bound|
          next convert_range_wildcard_req(bound) if bound.include?("*")

          bound
        end

        lower_b =
          if ["(", "["].include?(lower_b) then nil
          elsif T.must(lower_b).start_with?("(") then "> #{T.must(lower_b).sub(/\(\s*/, '')}"
          else
            ">= #{T.must(lower_b).sub(/\[\s*/, '').strip}"
          end

        upper_b =
          if !upper_b then nil
          elsif [")", "]"].include?(upper_b) then nil
          elsif upper_b.end_with?(")") then "< #{upper_b.sub(/\s*\)/, '')}"
          else
            "<= #{upper_b.sub(/\s*\]/, '').strip}"
          end

        [lower_b, upper_b].compact
      end
      # rubocop:enable Metrics/PerceivedComplexity

      sig { params(req_string: String).returns(String) }
      def convert_range_wildcard_req(req_string)
        range_end = T.must(req_string[-1])
        defined_part = T.must(req_string.split("*").first)
        version = defined_part + "0"
        version += range_end if [")", "]"].include?(range_end)
        version
      end

      sig { params(req_string: String).returns(String) }
      def convert_wildcard_req(req_string)
        return ">= 0-a" if req_string == "*-*"

        return ">= 0" if req_string.start_with?("*")

        defined_part = T.must(req_string.split("*").first)
        suffix = defined_part.end_with?(".") ? "0" : "a"
        version = defined_part + suffix
        "~> #{version}"
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("nuget", Dependabot::Nuget::Requirement)
