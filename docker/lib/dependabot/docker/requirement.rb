# typed: strict
# frozen_string_literal: true

require "dependabot/utils"

module Dependabot
  module Docker
    # Lifted from the bundler package manager
    class Requirement < Gem::Requirement
      extend T::Sig
      # For consistency with other languages, we define a requirements array.
      # Ruby doesn't have an `OR` separator for requirements, so it always
      # contains a single element.
      sig { params(requirement_string: String).returns([Dependabot::Docker::Requirement]) }
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      sig { override.params(version: Dependabot::Docker::Version).returns(T::Boolean) }
      def satisfied_by?(version)
        super(version.release_part)
      end

      # Patches Gem::Requirement to make it accept requirement strings like
      # "~> 4.2.5, >= 4.2.5.1" without first needing to split them.
      sig { override.params(requirements: String).void }
      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          req_string.split(",").map(&:strip)
        end

        super(requirements)
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("docker", Dependabot::Docker::Requirement)
