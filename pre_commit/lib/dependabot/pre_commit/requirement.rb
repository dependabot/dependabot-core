# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/requirement"
require "dependabot/utils"

module Dependabot
  module PreCommit
    class Requirement < Dependabot::Requirement
      extend T::Sig

      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Requirement]) }
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end
    end
  end
end

Dependabot::Utils
  .register_requirement_class("pre_commit", Dependabot::PreCommit::Requirement)
