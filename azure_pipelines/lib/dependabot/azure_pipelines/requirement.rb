# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"

require "dependabot/azure_pipelines/version"

module Dependabot
  module AzurePipelines
    # A task reference pins an exact version rather than a range, so a requirement
    # string is either a bare version (`4`) or an operator form supplied through
    # `ignore` conditions in dependabot.yml (`>= 5`, `< 4.277`).
    class Requirement < Dependabot::Requirement
      extend T::Sig

      sig do
        override
          .params(requirement_string: T.nilable(String))
          .returns(T::Array[Dependabot::Requirement])
      end
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      sig { params(requirements: T.nilable(String)).void }
      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          req_string&.split(",")&.map(&:strip)
        end.compact

        super
      end
    end
  end
end

Dependabot::Utils.register_requirement_class("azure_pipelines", Dependabot::AzurePipelines::Requirement)
