# frozen_string_literal: true

require "dependabot/utils"

module Dependabot
  module Swift
    class Requirement < Gem::Requirement
    end
  end
end

Dependabot::Utils.
  register_requirement_class("swift", Dependabot::Swift::Requirement)
