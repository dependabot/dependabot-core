# typed: strong
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module DotnetSdk
    class Version < Dependabot::Version
    end
  end
end

Dependabot::Utils
  .register_version_class("dotnet_sdk", Dependabot::DotnetSdk::Version)
