# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/helm/version"

module Dependabot
  module Helm
    class Requirement < Gem::Requirement
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end
    end
  end
end

Dependabot::Utils.register_requirement_class("helm", Dependabot::Helm::Requirement)
