# typed: strong
# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/pre_commit/update_checker"

module Dependabot
  module Prek
    # prek resolves remote hook versions identically to pre-commit (git tags and
    # commit SHAs), so the entire update-checking flow is reused unchanged.
    class UpdateChecker < Dependabot::PreCommit::UpdateChecker
    end
  end
end

Dependabot::UpdateCheckers
  .register("prek", Dependabot::Prek::UpdateChecker)
