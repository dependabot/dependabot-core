# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/requirement"
require "dependabot/utils"
require "dependabot/devbox/version"

# Devbox constraints are nixpkgs version prefixes declared as `name@constraint`
# in devbox.json. We translate the prefix form into Gem::Requirement strings:
#   latest   -> ">= 0"       (track the newest release)
#   3        -> "~> 3.0"     (pin the major line)
#   3.10     -> "~> 3.10.0"  (pin the minor line)
#   3.10.19  -> "= 3.10.19"  (pin an exact version)

module Dependabot
  module Devbox
    class Requirement < Dependabot::Requirement
      extend T::Sig

      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      sig { params(requirements: T.nilable(T.any(String, T::Array[String]))).void }
      def initialize(*requirements)
        constraints = requirements.flatten.compact.map do |req_string|
          convert_devbox_constraint_to_ruby_constraint(req_string.strip)
        end
        constraints = [">= 0"] if constraints.empty?

        super(constraints)
      end

      private

      sig { params(constraint: String).returns(String) }
      def convert_devbox_constraint_to_ruby_constraint(constraint)
        return ">= 0" if constraint.empty? || constraint == Version::LATEST

        segments = constraint.split(".")
        case segments.length
        when 1, 2 then "~> #{constraint}.0"
        else "= #{constraint}"
        end
      end
    end
  end
end

Dependabot::Utils.register_requirement_class("devbox", Dependabot::Devbox::Requirement)
