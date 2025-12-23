# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/lean/version"

module Dependabot
  module Lean
    class Requirement < Dependabot::Requirement
      extend T::Sig

      # Lean toolchain files use exact versions only, no version ranges
      sig do
        override
          .params(requirement_string: T.nilable(String))
          .returns(T::Array[Dependabot::Requirement])
      end
      def self.requirements_array(requirement_string)
        return [] if requirement_string.nil? || requirement_string.strip.empty?

        # Lean uses exact versions only
        [new("= #{requirement_string.strip}")]
      end

      sig { params(requirements: T.nilable(T.any(String, T::Array[String]))).void }
      def initialize(*requirements)
        requirements = requirements.flatten.map do |req_string|
          req = T.must(req_string).strip
          # If it's just a version number, treat it as exact
          req.match?(/^[<>=~!]/) ? req : "= #{req}"
        end

        super(requirements)
      end

      sig { override.params(version: Gem::Version).returns(T::Boolean) }
      def satisfied_by?(version)
        lean_version = case version
                       when Lean::Version then version
                       else Lean::Version.new(version.to_s)
                       end

        super(lean_version)
      rescue ArgumentError
        false
      end
    end
  end
end

Dependabot::Utils.register_requirement_class("lean", Dependabot::Lean::Requirement)
