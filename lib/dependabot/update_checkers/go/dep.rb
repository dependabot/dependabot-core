# frozen_string_literal: true

require "dependabot/update_checkers/base"

module Dependabot
  module UpdateCheckers
    module Go
      class Dep < Dependabot::UpdateCheckers::Base
        def latest_version
          # Hit the registry for this dependency and get its latest version
        end

        def latest_resolvable_version
          # Resolving the dependency files to get the latest version of
          # this dependency that doesn't cause conflicts is hard, and needs to
          # be done through a language helper that piggy-backs off of the
          # package manager's own resolution logic (see PHP, for example).
        end

        def updated_requirements
          # If the dependency file needs to be updated we store the updated
          # requirements on the dependency.
          dependency.requirements
        end

        private

        def latest_version_resolvable_with_full_unlock?
          # Full unlock checks aren't implemented for Go (yet)
          false
        end

        def updated_dependencies_after_full_unlock
          raise NotImplementedError
        end
      end
    end
  end
end
