# frozen_string_literal: true

require "dependabot/update_checkers"
require "dependabot/update_checkers/base"

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
