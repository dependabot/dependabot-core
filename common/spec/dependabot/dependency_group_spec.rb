# frozen_string_literal: true

require "dependabot/dependency_group"

RSpec.describe Dependabot::DependencyGroup do
  describe "#name" do
    it "returns the name" do
      my_dependency_group_name = "darren-from-work"
      dependency_group = described_class.new(my_dependency_group_name)

      expect(dependency_group.name).to eq(my_dependency_group_name)
    end
  end
end
