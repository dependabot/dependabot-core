# typed: strong
# frozen_string_literal: true

require "dependabot/pre_commit/version"
require "dependabot/utils"

module Dependabot
  module Prek
    # prek is configuration-compatible with pre-commit, so version comparison
    # is identical. Subclass to register a distinct "prek" version class.
    class Version < Dependabot::PreCommit::Version
    end
  end
end

Dependabot::Utils
  .register_version_class("prek", Dependabot::Prek::Version)
