# frozen_string_literal: true

require "dependabot/pull_request_creator/branch_namer/dependency_group_strategy"

RSpec.describe Dependabot::PullRequestCreator::BranchNamer::DependencyGroupStrategy do
  describe "#new_branch_name" do
    it "returns the name of the dependency group" do
      dependency_group = double("DependencyGroup", name: "my_dependency_group")
      strategy = described_class.new(
        dependencies: [],
        files: [],
        target_branch: "main",
        dependency_group: dependency_group
      )

      expect(strategy.new_branch_name).to eq(dependency_group.name)
    end
  end
end
