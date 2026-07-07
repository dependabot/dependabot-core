# typed: strict
# frozen_string_literal: true

require "dependabot/npm_and_yarn/package_name"

# nub.lock is pnpm-lock v9; npm/pnpm package-naming rules are identical, so
# nub delegates to npm_and_yarn's PackageName rather than duplicating it.
module Dependabot
  module Nub
    PackageName = Dependabot::NpmAndYarn::PackageName
  end
end
