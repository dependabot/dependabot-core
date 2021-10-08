# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/nuget/version"

Dependabot::Utils.register_version_class("cake", Dependabot::Nuget::Version)
