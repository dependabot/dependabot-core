# typed: strong
# frozen_string_literal: true

require "dependabot/requirement"
require "dependabot/utils"

module Dependabot
  module DotnetSdk
    class Requirement < Dependabot::Requirement
      AND_SEPARATOR = /(?<=[a-zA-Z0-9*])\s+(?:&+\s+)?(?!\s*[|-])/

      # For consistency with other languages, we define a requirements array.
      # global.json don't have an `OR` separator for requirements, so it
      # always contains a single element.
      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Dependabot::Requirement]) }
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      # Patches Gem::Requirement to make it accept requirement strings like
      # "~> 4.2.5, >= 4.2.5.1" without first needing to split them.
      sig { params(requirements: T.nilable(String)).void }
      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          req_string&.split(",")&.map(&:strip)
        end.compact

        super(requirements)
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("dotnet_sdk", Dependabot::DotnetSdk::Requirement)
