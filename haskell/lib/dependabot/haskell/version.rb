# frozen_string_literal: true

# version numbers are based on Haskell Package Versioning Policy (PVP).
# docs may be found at https://pvp.haskell.org/
# PVP allows up to 4 numerical segments like `0.0.0.0`,
# ignoring any tags after a dash e.g. `0.0.0.0-a`.
# as such, it appears to be a subset of Ruby's `Gem::Version`,
# so we should be able to just hook into that.

require "dependabot/utils"

module Dependabot
  module Haskell
    class Version < Gem::Version
    end
  end
end

Dependabot::Utils.
  register_version_class("haskell", Dependabot::Haskell::Version)
