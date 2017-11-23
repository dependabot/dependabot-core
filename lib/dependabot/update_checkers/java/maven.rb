# frozen_string_literal: true

require "dependabot/update_checkers/base"
require "dependabot/git_commit_checker"

module Dependabot
  module UpdateCheckers
    module Java
      class Maven < Dependabot::UpdateCheckers::Base
        def latest_version
          # TODO: Hit the registry and get the latest possible version
        end

        def latest_resolvable_version
          # TODO: Resolve the pom.xml to find the latest version we could update
          # to without updating any other dependencies at the same time
        end

        def updated_requirements
          # TODO: Update the original requirement (from the pom.xml)
          # to accommodate the latest version
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for Yarn (yet)
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end
      end
    end
  end
end
