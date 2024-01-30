# typed: true
# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/errors"

module DummyPackageManager
  class UpdateChecker < Dependabot::UpdateCheckers::Base
    def latest_version
      "9.9.9"
    end

    def up_to_date?
      false
    end

    def can_update?(*)
      true
    end

    def latest_resolvable_version
      latest_version
    end

    def updated_requirements
      dependency.requirements.map do |req|
        req.merge(requirement: "9.9.9")
      end
    end
  end
end

Dependabot::UpdateCheckers.register("dummy", DummyPackageManager::UpdateChecker)
