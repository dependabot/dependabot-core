# frozen_string_literal: true

require "json"
require "yaml"

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"
require "dependabot/git_commit_checker"
require "dependabot/shared_helpers"
require "dependabot/swift/requirement"
require "dependabot/swift/version"

module Dependabot
  module Swift
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      def latest_version
        raise NotImplementedError
      end

      def latest_resolvable_version
        raise NotImplementedError
      end

      def latest_resolvable_version_with_no_unlock
        raise NotImplementedError
      end

      def updated_requirements
        raise NotImplementedError
      end
    end
  end
end

Dependabot::UpdateCheckers.
  register("swift", Dependabot::Swift::UpdateChecker)
