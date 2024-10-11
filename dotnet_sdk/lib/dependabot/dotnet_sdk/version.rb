# typed: strong
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module DotnetSdk
    # The .NET SDK versioning scheme is not semver compliant.
    # However, for simpliticy, we will treat it as semver.
    # See: https://learn.microsoft.com/en-us/dotnet/core/versions/#versioning-details
    class Version < Dependabot::Version
    end
  end
end

Dependabot::Utils
  .register_version_class("dotnet_sdk", Dependabot::DotnetSdk::Version)
