# frozen_string_literal: true

require "dependabot/utils"

module Dependabot
  module Puppet
    class Version < Gem::Version
    end
  end
end

Dependabot::Utils.register_version_class("puppet", Dependabot::Puppet::Version)
