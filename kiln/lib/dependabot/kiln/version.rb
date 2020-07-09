# frozen_string_literal: true

require "dependabot/utils"

module Dependabot
  module Kiln
    class Version < Gem::Version
    end
  end
end

Dependabot::Utils.
    register_version_class("kiln", Dependabot::Kiln::Version)

