# typed: strict
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module Powershell
    # PowerShell module versions follow standard semantic versioning
    # (Major.Minor.Build.Revision), so no custom comparison logic is needed
    # beyond what Dependabot::Version already provides.
    class Version < Dependabot::Version
      extend T::Sig
    end
  end
end

Dependabot::Utils
  .register_version_class("powershell", Dependabot::Powershell::Version)
