# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

# PHP pre-release versions use 1.0.1-rc1 syntax, which Gem::Version
# converts into 1.0.1.pre.rc1. We override the `to_s` method to stop that
# alteration.

module Dependabot
  module Composer
    class Version < Dependabot::Version
      def initialize(version)
        @version_string = version.to_s
        super
      end

      def to_s
        @version_string
      end
    end
  end
end

Dependabot::Utils.
  register_version_class("composer", Dependabot::Composer::Version)
