# frozen_string_literal: true

require "dependabot/pull_request_creator/branch_namer/group_rule_strategy"

RSpec.describe Dependabot::PullRequestCreator::BranchNamer::GroupRuleStrategy do
  describe "#new_branch_name" do
    it "returns the name of the group rule" do
      group_rule = double("GroupRule", name: "my_group_rule")
      strategy = described_class.new(
        dependencies: [],
        files: [],
        target_branch: "main",
        group_rule: group_rule
      )

      expect(strategy.new_branch_name).to eq(group_rule.name)
    end
  end
end
