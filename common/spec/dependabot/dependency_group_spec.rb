# frozen_string_literal: true

require "dependabot/dependency_group"
require "dependabot/dependency"

# TODO: Once the Updater has been merged into Core, we should test this
# using the DependencyGroupEngine methods instead of mocking the functionality
RSpec.describe Dependabot::DependencyGroup do
  let(:dependency_group) { described_class.new(name: name, rules: rules) }
  let(:name) { "test_group" }
  let(:rules) { { "patterns" => ["test-*"] } }

  let(:test_dependency1) do
    Dependabot::Dependency.new(
      name: "test-dependency-1",
      package_manager: "bundler",
      version: "1.1.0",
      requirements: [
        {
          file: "Gemfile",
          requirement: "~> 1.1.0",
          groups: ["test"],
          source: nil
        }
      ]
    )
  end

  let(:test_dependency2) do
    Dependabot::Dependency.new(
      name: "test-dependency-2",
      package_manager: "bundler",
      version: "1.1.0",
      requirements: [
        {
          file: "Gemfile",
          requirement: "~> 1.1.0",
          groups: ["test"],
          source: nil
        }
      ]
    )
  end

  let(:production_dependency) do
    Dependabot::Dependency.new(
      name: "another-dependency",
      package_manager: "bundler",
      version: "1.1.0",
      requirements: [
        {
          file: "Gemfile",
          requirement: "~> 1.1.0",
          groups: ["default"],
          source: nil
        }
      ]
    )
  end

  # Mock out the dependency-type == production check for Bundler
  let(:production_checker) do
    lambda do |gemfile_groups|
      return true if gemfile_groups.empty?
      return true if gemfile_groups.include?("runtime")
      return true if gemfile_groups.include?("default")

      gemfile_groups.any? { |g| g.include?("prod") }
    end
  end

  before do
    allow(Dependabot::Dependency).to receive(:production_check_for_package_manager).and_return(production_checker)
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
    context "when the rules include patterns" do
      let(:rules) do
        {
          "patterns" => ["test-*", "nothing-matches-this"],
          "exclude-patterns" => ["*-2"]
        }
      end

      context "before dependencies are assigned to the group" do
        it "returns true if the dependency matches a pattern" do
          expect(dependency_group.dependencies).to eq([])
          expect(dependency_group.contains?(test_dependency1)).to be_truthy
        end

        it "returns false if the dependency is specifically excluded" do
          expect(dependency_group.dependencies).to eq([])
          expect(dependency_group.contains?(test_dependency2)).to be_falsey
        end

        it "returns false if the dependency does not match any patterns" do
          expect(dependency_group.dependencies).to eq([])
          expect(dependency_group.contains?(production_dependency)).to be_falsey
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

        it "returns false if the dependency is specifically excluded" do
          expect(dependency_group.dependencies).to include(test_dependency1)
          expect(dependency_group.contains?(test_dependency2)).to be_falsey
        end

        it "returns false if the dependency is not in the dependency list and does not match a pattern" do
          expect(dependency_group.dependencies).to include(test_dependency1)
          expect(dependency_group.contains?(production_dependency)).to be_falsey
        end
      end
    end

    context "when the rules specify a dependency-type" do
      let(:rules) do
        {
          "dependency-type" => "production"
        }
      end

      it "returns true if the dependency matches the specified type" do
        expect(dependency_group.contains?(production_dependency)).to be_truthy
      end

      it "returns false if the dependency does not match the specified type" do
        expect(dependency_group.contains?(test_dependency1)).to be_falsey
        expect(dependency_group.contains?(test_dependency2)).to be_falsey
      end
    end

    context "when the rules specify a mix of dependency-types" do
      let(:rules) do
        {
          "patterns" => ["*dependency*"],
          "exclude-patterns" => ["*-2"],
          "dependency-type" => "development"
        }
      end

      it "returns true if the dependency matches the specified type and a pattern" do
        expect(dependency_group.contains?(test_dependency1)).to be_truthy
      end

      it "returns false if the dependency only matches the pattern" do
        expect(dependency_group.contains?(production_dependency)).to be_falsey
      end

      it "returns false if the dependency matches the specified type and pattern but is excluded" do
        expect(dependency_group.contains?(test_dependency2)).to be_falsey
      end
    end
  end

  describe "#to_config_yaml" do
    let(:rules) do
      {
        "patterns" => ["test-*", "nothing-matches-this"],
        "exclude-patterns" => ["*-2"]
      }
    end

    it "renders the group to match our configuration file" do
      expect(dependency_group.to_config_yaml).to eql(<<~YAML)
        groups:
          test_group:
            patterns:
            - test-*
            - nothing-matches-this
            exclude-patterns:
            - "*-2"
      YAML
    end
  end
end
