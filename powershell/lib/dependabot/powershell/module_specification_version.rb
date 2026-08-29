# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Powershell
    # Numeric version used by PowerShell's ModuleSpecification fields.
    class ModuleSpecificationVersion
      extend T::Sig

      MAX_COMPONENT = 2_147_483_647
      MIN_COMPONENT_COUNT = 2
      MAX_COMPONENT_COUNT = 4
      COMPONENT_PATTERN = /\A\s*[+-]?[0-9]+\s*\z/

      sig { params(version: String).returns(T.nilable(ModuleSpecificationVersion)) }
      def self.parse(version)
        components = version.split(".", -1)
        return unless components.length.between?(MIN_COMPONENT_COUNT, MAX_COMPONENT_COUNT)
        return unless components.all? { |component| component.match?(COMPONENT_PATTERN) }

        numeric_components = components.map { |component| Integer(component, 10) }
        return unless numeric_components.all? { |component| component.between?(0, MAX_COMPONENT) }

        new(numeric_components)
      end

      sig { params(version: String).returns(T.nilable(String)) }
      def self.normalize(version)
        parse(version)&.to_s
      end

      sig { params(left: String, right: String).returns(T.nilable(Integer)) }
      def self.compare(left, right)
        left_version = parse(left)
        right_version = parse(right)
        return unless left_version && right_version

        left_version.compare(right_version)
      end

      sig { params(components: T::Array[Integer]).void }
      def initialize(components)
        @components = T.let(components.freeze, T::Array[Integer])
      end

      sig { params(other: ModuleSpecificationVersion).returns(Integer) }
      def compare(other)
        comparison_components <=> other.comparison_components
      end

      sig { override.returns(String) }
      def to_s
        components.join(".")
      end

      protected

      sig { returns(T::Array[Integer]) }
      attr_reader :components

      sig { returns(T::Array[Integer]) }
      def comparison_components
        components + ([-1] * (MAX_COMPONENT_COUNT - components.length))
      end
    end
  end
end
