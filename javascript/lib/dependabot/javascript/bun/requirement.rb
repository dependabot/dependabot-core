# typed: strong
# frozen_string_literal: true

module Dependabot
  module Javascript
    module Bun
      class Requirement < Dependabot::Javascript::Requirement
      end
    end
  end
end

Dependabot::Utils.register_requirement_class(
  "bun",
  Dependabot::Javascript::Bun::Requirement
)
