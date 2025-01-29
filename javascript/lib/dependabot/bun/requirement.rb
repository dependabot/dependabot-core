# typed: true
# frozen_string_literal: true

module Dependabot
  module Bun
    class Requirement < Dependabot::Javascript::Requirement
    end
  end
end

Dependabot::Utils.register_requirement_class(
  "bun",
  Dependabot::Bun::Requirement
)
