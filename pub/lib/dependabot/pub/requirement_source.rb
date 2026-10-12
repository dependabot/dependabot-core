# typed: strict
# frozen_string_literal: true

require "dependabot/dependency_requirement"

module Dependabot
  module Pub
    class RequirementSource
      extend T::Sig

      sig { params(requirement: T.nilable(Dependabot::DependencyRequirement)).void }
      def initialize(requirement)
        @requirement = requirement
      end

      sig { returns(T.nilable(String)) }
      def type
        requirement&.source_string("type")
      end

      sig { params(key: String).returns(T.nilable(String)) }
      def description_string(key)
        description = description_hash
        return unless description

        value = description.key?(key.to_sym) ? description[key.to_sym] : description[key]
        return if value.nil?
        return value if value.is_a?(String)

        raise TypeError, "source description #{key} must be a string or nil"
      end

      private

      sig { returns(T.nilable(Dependabot::DependencyRequirement)) }
      attr_reader :requirement

      sig { returns(T.nilable(Dependabot::DependencyRequirement::ObjectHash)) }
      def description_hash
        source = requirement&.source_hash
        return unless source

        value = source.key?(:description) ? source[:description] : source["description"]
        return if value.nil?
        unless value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) || key.is_a?(Symbol) }
          raise TypeError, "source description must be a hash with string or symbol keys"
        end

        value
      end
    end
  end
end
