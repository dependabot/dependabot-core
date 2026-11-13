# typed: strict
# frozen_string_literal: true

require "dependabot/dependency_group"
require "dependabot/dependency"

# TODO: Once the Updater has been merged into Core, we should test this
# using the DependencyGroupEngine methods instead of mocking the functionality
RSpec.describe Dependabot::DependencyGroup do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::DependencyGroup) } # rubocop:disable RSpec/DescribedClass -- Signatures need concrete types.
  let(:dependency_group) { described_class.new(name: name, rules: rules) }

  sig { returns(String) }
  let(:name) { "test_group" }

  sig { returns(T::Hash[String, T.any(String, T::Array[String])]) }
  let(:rules) { { "patterns" => ["test-*"] } }

  sig { returns(Dependabot::Dependency) }
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

  sig { returns(Dependabot::Dependency) }
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

  sig { returns(Dependabot::Dependency) }
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
  sig { returns(T.proc.params(gemfile_groups: T::Array[String]).returns(T::Boolean)) }
  let(:production_checker) do
    lambda do |gemfile_groups|
      gemfile_groups.empty? ||
        gemfile_groups.include?("runtime") ||
        gemfile_groups.include?("default") ||
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

  describe ".subgroup_name" do
    it "builds a subgroup name for a normal dependency" do
      expect(described_class.subgroup_name(parent_name: "frontend", dependency_name: "react")).to eq("frontend/react")
    end

    it "builds a subgroup name for a scoped dependency" do
      expect(described_class.subgroup_name(parent_name: "frontend", dependency_name: "@scope/business"))
        .to eq("frontend/@scope/business")
    end
  end

  describe ".parent_name_from_subgroup" do
    it "extracts the parent name for a normal dependency" do
      expect(described_class.parent_name_from_subgroup(subgroup_name: "frontend/react", dependency_name: "react"))
        .to eq("frontend")
    end

    it "extracts the parent name for a scoped dependency" do
      expect(
        described_class.parent_name_from_subgroup(
          subgroup_name: "frontend/@scope/business",
          dependency_name: "@scope/business"
        )
      ).to eq("frontend")
    end

    it "returns nil when the dependency suffix does not match" do
      expect(described_class.parent_name_from_subgroup(subgroup_name: "frontend/react", dependency_name: "rails"))
        .to be_nil
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
      sig { override.returns(T::Hash[String, T.any(String, T::Array[String])]) }
      let(:rules) do
        {
          "patterns" => ["test-*", "nothing-matches-this"],
          "exclude-patterns" => ["*-2"]
        }
      end

      context "when no dependencies are assigned to the group" do
        it "returns true if the dependency matches a pattern" do
          expect(dependency_group.dependencies).to eq([])
          expect(dependency_group.contains?(test_dependency1)).to be(true)
        end

        it "returns false if the dependency is specifically excluded" do
          expect(dependency_group.dependencies).to eq([])
          expect(dependency_group.contains?(test_dependency2)).to be(false)
        end

        it "returns false if the dependency does not match any patterns" do
          expect(dependency_group.dependencies).to eq([])
          expect(dependency_group.contains?(production_dependency)).to be(false)
        end
      end

      context "when dependencies are assigned to the group" do
        before do
          dependency_group.dependencies << test_dependency1
        end

        it "returns true if the dependency is in the dependency list" do
          expect(dependency_group.dependencies).to include(test_dependency1)
          expect(dependency_group.contains?(test_dependency1)).to be(true)
        end

        it "returns false if the dependency is specifically excluded" do
          expect(dependency_group.dependencies).to include(test_dependency1)
          expect(dependency_group.contains?(test_dependency2)).to be(false)
        end

        it "returns false if the dependency is not in the dependency list and does not match a pattern" do
          expect(dependency_group.dependencies).to include(test_dependency1)
          expect(dependency_group.contains?(production_dependency)).to be(false)
        end
      end
    end

    context "when the rules specify a dependency-type" do
      sig { override.returns(T::Hash[String, T.any(String, T::Array[String])]) }
      let(:rules) do
        {
          "dependency-type" => "production"
        }
      end

      it "returns true if the dependency matches the specified type" do
        expect(dependency_group.contains?(production_dependency)).to be(true)
      end

      it "returns false if the dependency does not match the specified type" do
        expect(dependency_group.contains?(test_dependency1)).to be(false)
        expect(dependency_group.contains?(test_dependency2)).to be(false)
      end

      context "when a dependency is specifically excluded" do
        sig { override.returns(T::Hash[String, T.any(String, T::Array[String])]) }
        let(:rules) do
          {
            "dependency-type" => "production",
            "exclude-patterns" => [production_dependency.name]
          }
        end

        it "returns false even if the dependency matches the specified type" do
          expect(dependency_group.contains?(production_dependency)).to be(false)
        end
      end
    end

    context "when the rules specify a mix of patterns and dependency-types" do
      sig { override.returns(T::Hash[String, T.any(String, T::Array[String])]) }
      let(:rules) do
        {
          "patterns" => ["*dependency*"],
          "exclude-patterns" => ["*-2"],
          "dependency-type" => "development"
        }
      end

      it "returns true if the dependency matches the specified type and a pattern" do
        expect(dependency_group.contains?(test_dependency1)).to be(true)
      end

      it "returns false if the dependency only matches the pattern" do
        expect(dependency_group.contains?(production_dependency)).to be(false)
      end

      it "returns false if the dependency matches the specified type and pattern but is excluded" do
        expect(dependency_group.contains?(test_dependency2)).to be(false)
      end
    end
  end

  describe "#to_config_yaml" do
    sig { override.returns(T::Hash[String, T.any(String, T::Array[String])]) }
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

  describe "#group_by" do
    context "when rules do not contain group-by" do
      sig { override.returns(Dependabot::DependencyGroup) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
      let(:dependency_group) { described_class.new(name: name, rules: rules) }

      it "returns nil" do
        expect(dependency_group.group_by).to be_nil
      end
    end

    context "when rules contain group-by" do
      sig { returns(T::Hash[String, T.any(String, T::Array[String])]) }
      let(:rules_with_group_by) { { "patterns" => ["test-*"], "group-by" => "dependency-name" } }

      sig { override.returns(Dependabot::DependencyGroup) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
      let(:dependency_group) { described_class.new(name: name, rules: rules_with_group_by) }

      it "returns the group-by value from rules" do
        expect(dependency_group.group_by).to eq("dependency-name")
      end
    end
  end

  describe "#group_by_dependency_name?" do
    sig { returns(T::Hash[String, T.any(String, T::Array[String])]) }
    let(:rules_with_group_by) { { "patterns" => ["test-*"], "group-by" => "dependency-name" } }

    sig { returns(T::Hash[String, T.any(String, T::Array[String])]) }
    let(:rules_with_other_group_by) { { "patterns" => ["test-*"], "group-by" => "something-else" } }

    context "when rules contain group-by: dependency-name" do
      sig { override.returns(Dependabot::DependencyGroup) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
      let(:dependency_group) { described_class.new(name: name, rules: rules_with_group_by) }

      it "returns true" do
        expect(dependency_group.group_by_dependency_name?).to be(true)
      end
    end

    context "when rules do not contain group-by" do
      sig { override.returns(Dependabot::DependencyGroup) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
      let(:dependency_group) { described_class.new(name: name, rules: rules) }

      it "returns false" do
        expect(dependency_group.group_by_dependency_name?).to be(false)
      end
    end

    context "when rules contain a different group-by value" do
      sig { override.returns(Dependabot::DependencyGroup) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
      let(:dependency_group) { described_class.new(name: name, rules: rules_with_other_group_by) }

      it "returns false" do
        expect(dependency_group.group_by_dependency_name?).to be(false)
      end
    end
    # rubocop:enable RSpec/ScatteredLet
  end
end
