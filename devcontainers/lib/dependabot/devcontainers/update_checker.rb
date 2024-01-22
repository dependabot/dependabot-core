# typed: strong
# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

module Dependabot
  module Devcontainers
    class UpdateChecker < Dependabot::UpdateCheckers::Base
    end
  end
end

Dependabot::UpdateCheckers.register("devcontainers", Dependabot::Devcontainers::UpdateChecker)
