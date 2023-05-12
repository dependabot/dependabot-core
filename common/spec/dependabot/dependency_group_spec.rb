# frozen_string_literal: true

require "dependabot/dependency_group"
require "dependabot/dependency"

# TODO: Once the Updater has been merged into Core, we should test this
# using the DependencyGroupEngine methods instead of mocking the functionality
RSpec.describe Dependabot::DependencyGroup do
  let(:dependency_group) { described_class.new(name: name, rules: rules) }
  let(:name) { "test_group" }
  let(:rules) { ["test-*"] }

  let(:test_dependency1) do
    Dependabot::Dependency.new(
      name: "test-dependency-1",
      package_manager: "bundler",
      version: "1.1.0",
      requirements: [
        {
          file: "Gemfile",
          requirement: "~> 1.1.0",
          groups: [],
          source: nil
        }
      ]
    )
  end

  let(:test_dependency2) do
    Dependabot::Dependency.new(
      name: "another-test-dependency",
      package_manager: "bundler",
      version: "1.1.0",
      requirements: [
        {
          file: "Gemfile",
          requirement: "~> 1.1.0",
          groups: [],
          source: nil
        }
      ]
    )
  end

  describe "#name" do
    it "returns the name" do
      expect(dependency_group.name).to eq(name)
    end
  end

  describe "#rules" do
    it "returns a list of rules" do
      expect(dependency_group.rules).to eq(rules)
    end
  end

  describe "#dependencies" do
    context "when no dependencies are assigned to the group" do
      it "returns an empty list" do
        expect(dependency_group.dependencies).to eq([])
      end
    end

    context "when dependencies have been assigned" do
      before do
        dependency_group.dependencies << test_dependency1
      end

      it "returns the dependencies" do
        expect(dependency_group.dependencies).to include(test_dependency1)
        expect(dependency_group.dependencies).not_to include(test_dependency2)
      end
    end
  end

  describe "#contains?" do
    context "before dependencies are assigned to the group" do
      it "returns true if the dependency matches a rule" do
        expect(dependency_group.dependencies).to eq([])
        expect(dependency_group.contains?(test_dependency1)).to be_truthy
      end

      it "returns false if the dependency does not match a rule" do
        expect(dependency_group.dependencies).to eq([])
        expect(dependency_group.contains?(test_dependency2)).to be_falsey
      end
    end

    context "after dependencies are assigned to the group" do
      before do
        dependency_group.dependencies << test_dependency1
      end

      it "returns true if the dependency is in the dependency list" do
        expect(dependency_group.dependencies).to include(test_dependency1)
        expect(dependency_group.contains?(test_dependency1)).to be_truthy
      end

      it "returns false if the dependency is not in the dependency list and does not match a rule" do
        expect(dependency_group.dependencies).to include(test_dependency1)
        expect(dependency_group.contains?(test_dependency2)).to be_falsey
      end
    end
  end
end
