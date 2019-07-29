# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/puppet/version"

module Dependabot
  module Puppet
    class Requirement < Gem::Requirement
    end
  end
end

Dependabot::Utils.
  register_requirement_class("puppet", Dependabot::Puppet::Requirement)
