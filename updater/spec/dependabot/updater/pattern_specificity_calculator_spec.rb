# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_group"
require "dependabot/updater/pattern_specificity_calculator"

RSpec.describe Dependabot::Updater::PatternSpecificityCalculator do
  let(:calculator) { described_class.new }

  describe "#calculate_pattern_specificity" do
    it "returns highest score for exact matches" do
      score = calculator.calculate_pattern_specificity("nginx", "nginx")
      expect(score).to eq(1000)
    end

    it "returns lowest score for universal wildcard" do
      score = calculator.calculate_pattern_specificity("*", "nginx")
      expect(score).to eq(1)
    end

    it "returns medium score for patterns without wildcards" do
      score = calculator.calculate_pattern_specificity("nginx-exact", "nginx")
      expect(score).to eq(500)
    end

    it "calculates scores with wildcard penalties" do
      single_wildcard_score = calculator.calculate_pattern_specificity("docker*", "docker-compose")
      expect(single_wildcard_score).to be > 1
      expect(single_wildcard_score).to be < 500

      multi_wildcard_score = calculator.calculate_pattern_specificity("*docker*", "docker-compose")
      expect(multi_wildcard_score).to be < single_wildcard_score
    end

    it "includes length bonus for longer patterns" do
      short_pattern_score = calculator.calculate_pattern_specificity("doc*", "docker-compose")
      long_pattern_score = calculator.calculate_pattern_specificity("docker-very-long*", "docker-compose")

      expect(long_pattern_score).to be > short_pattern_score
    end

    context "with specific wildcard counts" do
      it "calculates correct penalty for single wildcard" do
        score = calculator.calculate_pattern_specificity("test*", "test-dep")
        expected = 100 - 10 + [4 - 5, 0].max # base_score - penalty + length_bonus
        expect(score).to eq(expected)
      end

      it "calculates correct penalty for multiple wildcards" do
        score = calculator.calculate_pattern_specificity("*test*", "test-dep")
        expected = 100 - 20 + [6 - 5, 0].max # base_score - (2 * 10) + length_bonus
        expect(score).to eq(expected)
      end
    end
  end

  describe "#calculate_group_specificity_for_dependency" do
    let(:dependency) { create_dependency("docker-compose", "2.0.0") }

    context "with explicit group members" do
      let(:group_with_explicit_dep) do
        instance_double(
          Dependabot::DependencyGroup,
          dependencies: [dependency],
          rules: { "patterns" => ["*"] }
        )
      end

      it "returns highest score for explicit group members" do
        score = calculator.calculate_group_specificity_for_dependency(group_with_explicit_dep, dependency)
        expect(score).to eq(1000)
      end
    end

    context "with pattern-based groups" do
      let(:universal_group) do
        instance_double(
          Dependabot::DependencyGroup,
          dependencies: [],
          rules: { "patterns" => ["*"] }
        )
      end

      let(:docker_group) do
        instance_double(
          Dependabot::DependencyGroup,
          dependencies: [],
          rules: { "patterns" => ["docker*"] }
        )
      end

      let(:exact_group) do
        instance_double(
          Dependabot::DependencyGroup,
          dependencies: [],
          rules: { "patterns" => ["docker-compose"] }
        )
      end

      before do
        allow(WildcardMatcher).to receive(:match?) do |pattern, name|
          case pattern
          when "*"
            true
          when "docker*"
            name.start_with?("docker")
          when "docker-compose"
            name == "docker-compose"
          else
            false
          end
        end
      end

      it "returns correct score for universal wildcard group" do
        score = calculator.calculate_group_specificity_for_dependency(universal_group, dependency)
        expect(score).to eq(1)
      end

      it "returns higher score for specific wildcard patterns" do
        score = calculator.calculate_group_specificity_for_dependency(docker_group, dependency)
        expect(score).to be > 1
        expect(score).to be < 1000
      end

      it "returns highest score for exact pattern matches" do
        score = calculator.calculate_group_specificity_for_dependency(exact_group, dependency)
        expect(score).to eq(1000)
      end

      it "compares specificity correctly across different groups" do
        universal_score = calculator.calculate_group_specificity_for_dependency(universal_group, dependency)
        docker_score = calculator.calculate_group_specificity_for_dependency(docker_group, dependency)
        exact_score = calculator.calculate_group_specificity_for_dependency(exact_group, dependency)

        expect(exact_score).to be > docker_score
        expect(docker_score).to be > universal_score
      end
    end

    context "with no patterns" do
      let(:no_patterns_group) do
        instance_double(
          Dependabot::DependencyGroup,
          dependencies: [],
          rules: {}
        )
      end

      it "returns medium score for groups without patterns" do
        score = calculator.calculate_group_specificity_for_dependency(no_patterns_group, dependency)
        expect(score).to eq(500)
      end
    end

    context "with multiple matching patterns" do
      let(:multi_pattern_group) do
        instance_double(
          Dependabot::DependencyGroup,
          dependencies: [],
          rules: { "patterns" => ["docker*", "*compose*", "*"] }
        )
      end

      before do
        allow(WildcardMatcher).to receive(:match?) do |pattern, name|
          case pattern
          when "docker*"
            name.start_with?("docker")
          when "*compose*"
            name.include?("compose")
          when "*"
            true
          else
            false
          end
        end
      end

      it "returns the highest specificity among matching patterns" do
        score = calculator.calculate_group_specificity_for_dependency(multi_pattern_group, dependency)

        docker_specificity = calculator.calculate_pattern_specificity("docker*", "docker-compose")
        compose_specificity = calculator.calculate_pattern_specificity("*compose*", "docker-compose")
        universal_specificity = calculator.calculate_pattern_specificity("*", "docker-compose")

        expected_max = [docker_specificity, compose_specificity, universal_specificity].max
        expect(score).to eq(expected_max)
      end
    end

    context "with no matching patterns" do
      let(:non_matching_group) do
        instance_double(
          Dependabot::DependencyGroup,
          dependencies: [],
          rules: { "patterns" => ["python*", "node*"] }
        )
      end

      before do
        allow(WildcardMatcher).to receive(:match?).and_return(false)
      end

      it "returns 0 for non-matching patterns" do
        score = calculator.calculate_group_specificity_for_dependency(non_matching_group, dependency)
        expect(score).to eq(0)
      end
    end
  end

  describe "#dependency_belongs_to_more_specific_group?" do
    let(:dependency) { create_dependency("docker-compose", "2.0.0") }
    let(:directory) { "/api" }

    let(:universal_group) do
      instance_double(
        Dependabot::DependencyGroup,
        name: "all-dependencies",
        dependencies: [],
        rules: { "patterns" => ["*"] }
      )
    end

    let(:docker_group) do
      instance_double(
        Dependabot::DependencyGroup,
        name: "docker-dependencies",
        dependencies: [],
        rules: { "patterns" => ["docker*"] }
      )
    end

    let(:exact_group) do
      instance_double(
        Dependabot::DependencyGroup,
        name: "exact-docker-compose",
        dependencies: [],
        rules: { "patterns" => ["docker-compose"] }
      )
    end

    let(:groups) { [universal_group, docker_group, exact_group] }

    let(:contains_checker) do
      proc do |group, dep, _dir|
        case group
        when universal_group
          true
        when docker_group
          dep.name.start_with?("docker")
        when exact_group
          dep.name == "docker-compose"
        else
          false
        end
      end
    end

    before do
      allow(calculator).to receive(:calculate_group_specificity_for_dependency) do |group, _dep|
        case group
        when universal_group
          1
        when docker_group
          95
        when exact_group
          1000
        else
          0
        end
      end
    end

    context "when current group is universal" do
      it "returns true when more specific groups exist" do
        result = calculator.dependency_belongs_to_more_specific_group?(
          universal_group, dependency, groups, contains_checker, directory
        )
        expect(result).to be true
      end
    end

    context "when current group is already most specific" do
      it "returns false for exact match group" do
        result = calculator.dependency_belongs_to_more_specific_group?(
          exact_group, dependency, groups, contains_checker, directory
        )
        expect(result).to be false
      end
    end

    context "when current group has maximum specificity" do
      let(:max_specificity_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "max-specificity",
          dependencies: [dependency],
          rules: {}
        )
      end

      it "returns false early for groups with specificity >= 1000" do
        allow(calculator).to receive(:calculate_group_specificity_for_dependency)
          .with(max_specificity_group, dependency)
          .and_return(1000)

        result = calculator.dependency_belongs_to_more_specific_group?(
          max_specificity_group, dependency, groups, contains_checker, directory
        )
        expect(result).to be false
      end
    end

    context "when dependency doesn't match other groups" do
      let(:non_docker_dependency) { create_dependency("nginx", "1.21.0") }

      let(:non_matching_contains_checker) do
        proc do |group, _dep, _dir|
          case group
          when universal_group
            true
          when docker_group, exact_group
            false
          else
            false
          end
        end
      end

      it "returns false when no other groups contain the dependency" do
        result = calculator.dependency_belongs_to_more_specific_group?(
          universal_group, non_docker_dependency, groups, non_matching_contains_checker, directory
        )
        expect(result).to be false
      end
    end

    context "when current group is excluded from comparison" do
      it "skips the current group in specificity comparison" do
        expect(contains_checker).not_to receive(:call).with(docker_group, dependency, directory)

        calculator.dependency_belongs_to_more_specific_group?(
          docker_group, dependency, groups, contains_checker, directory
        )
      end
    end

    context "with edge case specificities" do
      let(:equal_specificity_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "equal-specificity",
          dependencies: [],
          rules: { "patterns" => ["docker-*"] }
        )
      end

      let(:groups_with_equal) { [universal_group, docker_group, equal_specificity_group] }

      before do
        allow(calculator).to receive(:calculate_group_specificity_for_dependency) do |group, _dep|
          case group
          when universal_group
            1
          when docker_group, equal_specificity_group
            95
          else
            0
          end
        end
      end

      it "returns false when other groups have equal specificity" do
        equal_contains_checker = proc do |group, dep, _dir|
          case group
          when universal_group
            true
          when docker_group, equal_specificity_group
            dep.name.start_with?("docker")
          else
            false
          end
        end

        result = calculator.dependency_belongs_to_more_specific_group?(
          docker_group, dependency, groups_with_equal, equal_contains_checker, directory
        )
        expect(result).to be false
      end
    end
  end

  private

  def create_dependency(name, version)
    instance_double(
      Dependabot::Dependency,
      name: name,
      version: version
    )
  end
end
