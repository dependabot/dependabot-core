# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/requirement"
require "dependabot/utils"

module Dependabot
  module Bazel
    class Requirement < Dependabot::Requirement
      extend T::Sig

      # Bazel dependencies typically use exact versions, not version ranges
      # This class exists for consistency with Dependabot patterns but
      # may not be heavily used since Bazel tends to pin exact versions

      sig { params(requirement_string: String).returns(String) }
      def self.normalize_requirement(requirement_string)
        # Handle exact version specifications (most common in Bazel)
        return requirement_string if requirement_string.match?(/^[<>=~]/)

        # For bare version strings, treat as exact match
        return "= #{requirement_string}" if requirement_string.match?(/^\d+(\.\d+)*(-[\w\d.]+)?(\+[\w\d.]+)?$/)

        requirement_string
      end

      # This abstract method must be implemented
      sig do
        override
          .params(requirement_string: T.nilable(String))
          .returns(T::Array[Dependabot::Requirement])
      end
      def self.requirements_array(requirement_string)
        # For Bazel, most requirements are simple exact versions
        return [] if requirement_string.nil? || requirement_string.strip.empty?

        normalized = normalize_requirement(requirement_string)
        [new(normalized)]
      end

      # Override satisfied_by? to handle Bazel version specifics
      sig { override.params(version: Gem::Version).returns(T::Boolean) }
      def satisfied_by?(version)
        # For Bazel versions, delegate to the base class
        # but ensure we're working with proper version objects
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
