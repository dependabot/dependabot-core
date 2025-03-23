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
      return [new(nil)] if requirement_string.nil?

      requirement_string.split(AND_SEPARATOR).map do |req|
        new(req.strip)
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("silent", SilentPackageManager::Requirement)
