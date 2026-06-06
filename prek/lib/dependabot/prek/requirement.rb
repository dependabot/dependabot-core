# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/pre_commit/requirement"
require "dependabot/utils"

module Dependabot
  module Prek
    # prek shares pre-commit's requirement semantics; subclass to register a
    # distinct "prek" requirement class.
    class Requirement < Dependabot::PreCommit::Requirement
    end
  end
end

Dependabot::Utils
  .register_requirement_class("prek", Dependabot::Prek::Requirement)
