# frozen_string_literal: true

require "dependabot/utils"
require "rubygems_version_patch"

# Dotnet pre-release versions use 1.0.1-rc1 syntax, which Gem::Version
# converts into 1.0.1.pre.rc1. We override the `to_s` method to stop that
# alteration.
# Dotnet also supports build versions, separated with a "+".
module Dependabot
  module Paket
    class Version < Gem::Version

    end
  end
end

Dependabot::Utils.register_version_class("paket", Dependabot::Paket::Version)
