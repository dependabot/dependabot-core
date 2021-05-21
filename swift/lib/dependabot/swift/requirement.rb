# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/swift/version"

# Override all essential methods to make it possible to delegate all work to the
# dedicated Dart library for parsing and updating Dart version constraints.
module Dependabot
  module Swift
    class Requirement < Gem::Requirement
    end
  end
end

Dependabot::Utils.
  register_requirement_class("swift", Dependabot::Swift::Requirement)
