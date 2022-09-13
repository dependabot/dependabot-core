# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/terraform/version"

# Just ensures that Terraform requirements use Terraform versions
module Dependabot
  module Terraform
    class Requirement < Gem::Requirement
      # Override regex PATTERN from Gem::Requirement to add support for the
      # optional 'v' prefix to release tag names, which Terraform supports.
      # https://www.terraform.io/docs/registry/modules/publish.html#requirements
      OPERATORS = OPS.keys.map { |key| Regexp.quote(key) }.join("|").freeze
      PATTERN_RAW = "\\s*(#{OPERATORS})?\\s*v?(#{Gem::Version::VERSION_PATTERN})\\s*"
      PATTERN = /\A#{PATTERN_RAW}\z/.freeze

      def self.parse(obj)
        return ["=", Version.new(obj.to_s)] if obj.is_a?(Gem::Version)

        unless (matches = PATTERN.match(obj.to_s))
          msg = "Illformed requirement [#{obj.inspect}]"
          raise BadRequirementError, msg
        end

        return DefaultRequirement if matches[1] == ">=" && matches[2] == "0"

        [matches[1] || "=", Terraform::Version.new(matches[2])]
      end

      # For consistency with other languages, we define a requirements array.
      # Terraform doesn't have an `OR` separator for requirements, so it
      # always contains a single element.
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      # Patches Gem::Requirement to make it accept requirement strings like
      # "~> 4.2.5, >= 4.2.5.1" without first needing to split them.
      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          req_string.split(",").map(&:strip)
        end

        super(requirements)
      end
    end
  end
end

Dependabot::Utils.
  register_requirement_class("terraform", Dependabot::Terraform::Requirement)
