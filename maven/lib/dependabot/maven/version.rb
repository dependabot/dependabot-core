# typed: strong
# frozen_string_literal: true

require "dependabot/new_version"
require "dependabot/utils"

# See https://maven.apache.org/pom.html#Version_Order_Specification for details.

module Dependabot
  module Maven
    class Version < Dependabot::NewVersion
    end
  end
end

Dependabot::Utils.register_version_class("maven", Dependabot::Maven::Version)
