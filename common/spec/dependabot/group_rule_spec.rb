# frozen_string_literal: true

require "dependabot/group_rule"

RSpec.describe Dependabot::GroupRule do
  describe "#name" do
    it "returns the name" do
      my_group_rule_name = "Darren from work"
      group_rule = described_class.new(my_group_rule_name)

      expect(group_rule.name).to eq(my_group_rule_name)
    end
  end
end
