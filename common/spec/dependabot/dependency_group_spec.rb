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
          groups: [],
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
          groups: [],
          source: nil
        }
      ]
    )
  end

  let(:another_test_dependency) do
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

  describe "#ignored_versions_for" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "business",
        package_manager: "bundler",
        version: "1.8.0",
        requirements: [
          { file: "Gemfile", requirement: "~> 1.8.0", groups: [], source: nil }
        ]
      )
    end

    context "the group has not defined any update-type rules" do
      it "returns an empty array" do
        expect(dependency_group.ignored_versions_for(dependency)).to be_empty
      end
    end

    context "the group permits all update-types" do
      let(:rules) do
        {
          "update-types" => [
            "version-update:semver-major",
            "version-update:semver-minor",
            "version-update:semver-patch"
          ]
        }
      end

      it "returns an empty array" do
        expect(dependency_group.ignored_versions_for(dependency)).to be_empty
      end
    end

    context "when group only permits patch versions" do
      let(:rules) do
        {
          "update-types" => [
            "version-update:semver-major"
          ]
        }
      end

      it "returns ranges which ignore minor and patch updates" do
        expect(dependency_group.ignored_versions_for(dependency)).to eql([
          "> 1.8.0, < 1.9",
          ">= 1.9.a, < 2"
        ])
      end
    end

    context "when group only permits minor versions" do
      let(:rules) do
        {
          "update-types" => [
            "version-update:semver-minor"
          ]
        }
      end

      it "returns ranges which ignore major and patch updates" do
        expect(dependency_group.ignored_versions_for(dependency)).to eql([
          "> 1.8.0, < 1.9",
          ">= 2.a"
        ])
      end
    end

    context "when the group only permits patch versions" do
      let(:rules) do
        {
          "update-types" => [
            "version-update:semver-patch"
          ]
        }
      end

      it "returns ranges which ignore major and minor updates" do
        expect(dependency_group.ignored_versions_for(dependency)).to eql([
          ">= 1.9.a, < 2",
          ">= 2.a"
        ])
      end
    end

    context "when the group only permits minor and patch versions" do
      let(:rules) do
        {
          "update-types" => [
            "version-update:semver-minor",
            "version-update:semver-patch"
          ]
        }
      end

      it "returns ranges which ignore major and minor updates" do
        expect(dependency_group.ignored_versions_for(dependency)).to eql([
          ">= 2.a"
        ])
      end
    end

    context "when the group has duplicate update-types" do
      let(:rules) do
        {
          "update-types" => [
            "version-update:semver-major",
            "version-update:semver-major"
          ]
        }
      end

      it "ignores the duplication" do
        expect(dependency_group.ignored_versions_for(dependency)).to eql([
          "> 1.8.0, < 1.9",
          ">= 1.9.a, < 2"
        ])
      end
    end

    context "when the group has garbage update-types" do
      let(:rules) do
        {
          "update-types" => [
            "Never going to give you up, Never going to let you down"
          ]
        }
      end

      it "raises an exception when created" do
        expect { dependency_group }.
          to raise_error(ArgumentError, starting_with("The #{name} group has unexpected update-type(s):"))
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
          expect(dependency_group.contains?(another_test_dependency)).to be_falsey
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
          expect(dependency_group.contains?(another_test_dependency)).to be_falsey
        end
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
