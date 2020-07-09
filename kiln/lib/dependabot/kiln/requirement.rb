# frozen_string_literal: true

require "dependabot/utils"

module Dependabot
  module Kiln
    class Requirement < Gem::Requirement
    end
  end
end

Dependabot::Utils.
    register_requirement_class("kiln", Dependabot::Kiln::Requirement)

