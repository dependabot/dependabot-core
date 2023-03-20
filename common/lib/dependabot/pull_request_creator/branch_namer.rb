# frozen_string_literal: true

require "digest"

require "dependabot/metadata_finders"
require "dependabot/pull_request_creator"
require "dependabot/pull_request_creator/branch_namer/solo_strategy"

module Dependabot
  class PullRequestCreator
    class BranchNamer
      attr_reader :dependencies, :files, :target_branch, :separator, :prefix, :max_length, :group_rule

      def initialize(dependencies:, files:, target_branch:, group_rule: nil,
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
        strategy.new_branch_name
      end

      private

      def strategy
        @strategy ||=
          if group_rule.nil?
            SoloStrategy.new(
              dependencies: dependencies,
              files: files,
              target_branch: target_branch,
              separator: separator,
              prefix: prefix,
              max_length: max_length
            )
          else
            GroupRuleStrategy.new(
              dependencies: dependencies,
              files: files,
              target_branch: target_branch,
              group_rule: group_rule,
              separator: separator,
              prefix: prefix,
              max_length: max_length
            )
          end
      end
    end
  end
end
