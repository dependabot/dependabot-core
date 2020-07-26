# frozen_string_literal: true

require "dependabot/utils"
require "dependabot/paket/version"

# For details on .NET version constraints see:
# https://docs.microsoft.com/en-us/nuget/reference/package-versioning
module Dependabot
  module Paket
    class Requirement < Gem::Requirement

    end
  end
end

Dependabot::Utils.
  register_requirement_class("paket", Dependabot::Paket::Requirement)
