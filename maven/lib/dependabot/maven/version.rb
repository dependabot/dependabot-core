# typed: strong
# frozen_string_literal: true

require "dependabot/new_version"
require "dependabot/version"
require "dependabot/utils"

# Java versions use dots and dashes when tokenising their versions.
# Gem::Version converts a "-" to ".pre.", so we override the `to_s` method.
#
# See https://maven.apache.org/pom.html#Version_Order_Specification for details.

module Dependabot
  module Maven
    class Version < Dependabot::NewVersion
      sig { override.overridable.params(version: VersionParameter, _version_string: T.nilable(String)).void }
      def initialize(version, _version_string = nil)
        super(version.to_s.tr("_", "-"), version.to_s)
      end
    end
  end
end

Dependabot::Utils.register_version_class("maven", Dependabot::Maven::Version)
