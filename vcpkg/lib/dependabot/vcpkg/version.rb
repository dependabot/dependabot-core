# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/utils"
require "dependabot/version"

module Dependabot
  module Vcpkg
    class Version < Dependabot::Version
    end
  end
end

Dependabot::Utils.register_version_class("vcpkg", Dependabot::Vcpkg::Version)
