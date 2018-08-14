# frozen_string_literal: true

require "dependabot/utils/dotnet/version"

# For details on .NET version constraints see:
# https://docs.microsoft.com/en-us/nuget/reference/package-versioning
module Dependabot
  module Utils
    module Dotnet
      class Requirement < Gem::Requirement
        def self.parse(obj)
          if obj.is_a?(Gem::Version)
            return ["=", Utils::Dotnet::Version.new(obj.to_s)]
          end

          unless (matches = PATTERN.match(obj.to_s))
            msg = "Illformed requirement [#{obj.inspect}]"
            raise BadRequirementError, msg
          end

          return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"
          [matches[1] || "=", Utils::Dotnet::Version.new(matches[2])]
        end

        # For consistency with other langauges, we define a requirements array.
        # Dotnet doesn't have an `OR` separator for requirements, so it always
        # contains a single element.
        def self.requirements_array(requirement_string)
          [new(requirement_string)]
        end

        def initialize(*requirements)
          requirements = requirements.flatten.flat_map do |req_string|
            req_string.split(",").map do |r|
              convert_php_constraint_to_ruby_constraint(r.strip)
            end
          end

          super(requirements)
        end

        def satisfied_by?(version)
          version = Utils::Dotnet::Version.new(version.to_s)
          super
        end

        private

        def convert_php_constraint_to_ruby_constraint(req_string)
          return req_string unless req_string.include?("*")
          convert_wildcard_req(req_string)
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
end
