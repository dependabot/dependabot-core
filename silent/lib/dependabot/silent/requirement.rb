# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"

module SilentPackageManager
  class Requirement < Dependabot::Requirement
    extend T::Sig

    AND_SEPARATOR = /(?<=[a-zA-Z0-9*])\s+(?:&+\s+)?(?!\s*[|-])/

    sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Dependabot::Requirement]) }
    def self.requirements_array(requirement_string)
      return [] if requirement_string.nil?

      requirements = requirement_string.split(AND_SEPARATOR).map(&:strip)

      [new(requirements)]
    end
  end
end

Dependabot::Utils
  .register_requirement_class("silent", SilentPackageManager::Requirement)
