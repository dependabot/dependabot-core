# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/requirement"
require "dependabot/utils"

module Dependabot
  module Bazel
    class Requirement < Dependabot::Requirement
      extend T::Sig

      sig { params(requirement_string: String).returns(String) }
      def self.normalize_requirement(requirement_string)
        return requirement_string if requirement_string.match?(/^[<>=~]/)

        return "= #{requirement_string}" if requirement_string.match?(/^\d+(\.\d+)*(-[\w\d.]+)?(\+[\w\d.]+)?$/)

        requirement_string
      end

      sig do
        override
          .params(requirement_string: T.nilable(String))
          .returns(T::Array[Dependabot::Requirement])
      end
      def self.requirements_array(requirement_string)
        return [] if requirement_string.nil? || requirement_string.strip.empty?

        # Handle comma-separated constraints (e.g., ">= 1.0, < 2.0")
        constraints = requirement_string.split(",").map do |req_string|
          normalize_requirement(req_string.strip)
        end.reject(&:empty?)

        return [] if constraints.empty?

        [new(constraints)]
      end

      sig { params(requirements: T.nilable(T.any(String, T::Array[String]))).void }
      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          T.must(req_string).split(",").map(&:strip)
        end

        super(requirements)
      end

      sig { override.params(version: Gem::Version).returns(T::Boolean) }
      def satisfied_by?(version)
        bazel_version = case version
                        when Dependabot::Bazel::Version
                          version
                        else
                          Dependabot::Bazel::Version.new(version.to_s)
                        end

        super(bazel_version)
      rescue ArgumentError
        false
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("bazel", Dependabot::Bazel::Requirement)
