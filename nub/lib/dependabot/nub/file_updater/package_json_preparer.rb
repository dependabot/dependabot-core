# typed: strict
# frozen_string_literal: true

require "dependabot/npm_and_yarn/file_updater/package_json_preparer"
require "dependabot/nub/file_updater"

# Manifest preparation (ssh-source swap, workspace-prefix cleanup) is identical
# across pnpm-format tools; delegate to npm_and_yarn's PackageJsonPreparer.
module Dependabot
  module Nub
    class FileUpdater < Dependabot::FileUpdaters::Base
      PackageJsonPreparer = Dependabot::NpmAndYarn::FileUpdater::PackageJsonPreparer
    end
  end
end
