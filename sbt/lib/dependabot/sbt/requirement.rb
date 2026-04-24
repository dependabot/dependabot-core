# typed: strict
# frozen_string_literal: true

# NOTE: This file was scaffolded automatically but is OPTIONAL.
# If your ecosystem uses standard Gem::Requirement logic,
# you can safely delete this file and remove the require from lib/dependabot/sbt.rb

require "dependabot/requirement"
require "dependabot/utils"

module Dependabot
  module Sbt
    class Requirement < Dependabot::Requirement
      extend T::Sig

      sig do
        override
          .params(requirement_string: T.nilable(String))
          .returns(T::Array[Dependabot::Requirement])
      end
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end
    end
  end
end

Dependabot::Utils.register_requirement_class("sbt", Dependabot::Sbt::Requirement)
