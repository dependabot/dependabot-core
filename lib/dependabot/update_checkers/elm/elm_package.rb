# frozen_string_literal: true

require "dependabot/update_checkers/base"
require "dependabot/file_updaters/ruby/bundler/requirement_replacer"
require "dependabot/git_commit_checker"

module Dependabot
  module UpdateCheckers
    module Ruby
      class Bundler < Dependabot::UpdateCheckers::ElmPackage
        def latest_version
          raise NotImplementedError
        end

        def latest_resolvable_version
          raise NotImplementedError
        end

        alias latest_resolvable_version_with_no_unlock latest_resolvable_version

        def updated_requirements
          raise NotImplementedError
        end

        private

        def latest_version_resolvable_with_full_unlock?
          raise NotImplementedError
        end
      end
    end
  end
end
