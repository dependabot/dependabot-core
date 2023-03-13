# frozen_string_literal: true

module Dependabot
  class PullRequestCreator
    class BranchNamer
      class GroupRuleStrategy
        def initialize(dependencies:, files:, target_branch:, group_rule:,
                       separator: "/", prefix: "dependabot", max_length: nil)
          @dependencies  = dependencies
          @files         = files
          @target_branch = target_branch
          @group_rule    = group_rule
          @separator     = separator
          @prefix        = prefix
          @max_length    = max_length
        end

        def new_branch_name
          group_rule.name
        end

        private

        attr_reader :group_rule
      end
    end
  end
end
