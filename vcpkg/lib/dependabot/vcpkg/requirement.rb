# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"

module Dependabot
  module Vcpkg
    class Requirement < Dependabot::Requirement
      extend T::Sig

      # Vcpkg requirements are simple strings, so we can just return a single
      # requirement object for the given string.
      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Dependabot::Requirement]) }
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end
    end
  end
end

Dependabot::Utils.register_requirement_class("vcpkg", Dependabot::Vcpkg::Requirement)
