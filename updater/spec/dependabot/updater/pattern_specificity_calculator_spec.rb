# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_group"
require "dependabot/updater/pattern_specificity_calculator"

RSpec.describe Dependabot::Updater::PatternSpecificityCalculator do
  let(:calculator) { described_class.new }

  describe "#dependency_belongs_to_more_specific_group?" do
    let(:dependency) { create_dependency("docker-compose", "2.0.0") }
    let(:directory) { "/api" }

    let(:generic_group) do
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

    let(:explicit_group) do
      instance_double(
        Dependabot::DependencyGroup,
        name: "explicit-dependencies",
        dependencies: [dependency],
        rules: { "patterns" => ["other*"] }
      )
    end

    let(:all_groups) { [generic_group, docker_group, exact_group, explicit_group] }

    let(:contains_checker) do
      proc do |group, dep, _directory|
        case group
        when generic_group
          true
        when docker_group
          dep.name.start_with?("docker")
        when exact_group
          dep.name == "docker-compose"
        when explicit_group
          group.dependencies.include?(dep)
        else
          false
        end
      end
    end

    context "when current group has universal wildcard pattern" do
      it "returns true when dependency belongs to more specific pattern group" do
        result = calculator.dependency_belongs_to_more_specific_group?(
          generic_group, dependency, all_groups, contains_checker, directory
        )
        expect(result).to be true
      end

      it "returns true when dependency belongs to exact match group" do
        nginx_dep = create_dependency("nginx", "1.21.0")
        nginx_exact_group = instance_double(
          Dependabot::DependencyGroup,
          name: "nginx-exact",
          dependencies: [],
          rules: { "patterns" => ["nginx"] }
        )

        nginx_contains_checker = proc do |group, dep, _directory|
          case group
          when generic_group
            true
          when nginx_exact_group
            dep.name == "nginx"
          else
            false
          end
        end

        result = calculator.dependency_belongs_to_more_specific_group?(
          generic_group, nginx_dep, [generic_group, nginx_exact_group], nginx_contains_checker, directory
        )
        expect(result).to be true
      end
    end

    context "when dependency is excluded by current group" do
      let(:generic_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "all-dependencies",
          dependencies: [],
          rules: { "patterns" => ["*"], "exclude-patterns" => ["docker-compose"] }
        )
      end

      it "returns false even if other groups would match" do
        result = calculator.dependency_belongs_to_more_specific_group?(
          generic_group, dependency, all_groups, contains_checker, directory
        )
        expect(result).to be false
      end
    end

    context "when other groups restrict update types" do
      let(:docker_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "docker-dependencies",
          dependencies: [],
          rules: { "patterns" => ["docker*"], "update-types" => ["minor"] }
        )
      end

      let(:all_groups) { [generic_group, docker_group] }

      it "ignores more specific group when update_type is not allowed" do
        result = calculator.dependency_belongs_to_more_specific_group?(
          generic_group, dependency, all_groups, contains_checker, directory, update_type: "major"
        )
        expect(result).to be false
      end

      it "considers more specific group when update_type is allowed" do
        result = calculator.dependency_belongs_to_more_specific_group?(
          generic_group, dependency, all_groups, contains_checker, directory, update_type: "minor"
        )
        expect(result).to be true
      end
    end

    context "when other groups have different applies_to" do
      let(:generic_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "all-dependencies",
          dependencies: [],
          applies_to: "version-updates",
          rules: { "patterns" => ["*"] }
        )
      end

      let(:security_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "security-dependencies",
          dependencies: [],
          applies_to: "security-updates",
          rules: { "patterns" => ["docker*"] }
        )
      end

      let(:all_groups) { [generic_group, security_group] }

      let(:contains_checker) do
        proc do |group, dep, _directory|
          case group
          when generic_group
            true
          when security_group
            dep.name.start_with?("docker")
          else
            false
          end
        end
      end

      it "ignores groups with non-matching applies_to" do
        result = calculator.dependency_belongs_to_more_specific_group?(
          generic_group, dependency, all_groups, contains_checker, directory, applies_to: "version-updates"
        )
        expect(result).to be false
      end

      it "considers groups with matching applies_to" do
        result = calculator.dependency_belongs_to_more_specific_group?(
          generic_group, dependency, all_groups, contains_checker, directory, applies_to: "security-updates"
        )
        expect(result).to be true
      end
    end

    context "when current group has specific pattern" do
      it "returns true when dependency belongs to even more specific group" do
        result = calculator.dependency_belongs_to_more_specific_group?(
          docker_group, dependency, all_groups, contains_checker, directory
        )
        expect(result).to be true
      end

      it "returns false when no more specific group exists" do
        redis_dep = create_dependency("redis-client", "0.11.0")
        redis_group = instance_double(
          Dependabot::DependencyGroup,
          name: "redis-dependencies",
          dependencies: [],
          rules: { "patterns" => ["redis*"] }
        )

        redis_contains_checker = proc do |group, dep, _directory|
          case group
          when generic_group
            true
          when redis_group
            dep.name.start_with?("redis")
          else
            false
          end
        end

        result = calculator.dependency_belongs_to_more_specific_group?(
          redis_group, redis_dep, [generic_group, redis_group], redis_contains_checker, directory
        )
        expect(result).to be false
      end
    end

    context "when current group has exact match pattern" do
      it "returns false when current group is most specific" do
        result = calculator.dependency_belongs_to_more_specific_group?(
          exact_group, dependency, all_groups, contains_checker, directory
        )
        expect(result).to be false
      end
    end

    context "when current group has explicit dependency" do
      it "returns false when dependency is explicitly in the group" do
        result = calculator.dependency_belongs_to_more_specific_group?(
          explicit_group, dependency, all_groups, contains_checker, directory
        )
        expect(result).to be false
      end
    end

    context "when no other group contains the dependency" do
      it "returns false" do
        non_matching_contains_checker = proc { |_group, _dep, _directory| false }

        result = calculator.dependency_belongs_to_more_specific_group?(
          generic_group, dependency, all_groups, non_matching_contains_checker, directory
        )
        expect(result).to be false
      end
    end

    context "when current group has no patterns" do
      let(:no_patterns_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "patch-updates",
          dependencies: [],
          rules: { "update-types" => ["patch"] }
        )
      end

      it "returns false immediately without checking other groups" do
        # This test verifies the early return optimization
        # The contains_checker should never be called since we return early
        contains_checker_spy = proc do |_group, _dep, _directory|
          raise "contains_checker should not be called when group has no patterns"
        end

        result = calculator.dependency_belongs_to_more_specific_group?(
          no_patterns_group, dependency, all_groups, contains_checker_spy, directory
        )
        expect(result).to be false
      end

      it "returns false when group has nil patterns" do
        nil_patterns_group = instance_double(
          Dependabot::DependencyGroup,
          name: "nil-patterns",
          dependencies: [],
          rules: { "patterns" => nil, "update-types" => ["patch"] }
        )

        result = calculator.dependency_belongs_to_more_specific_group?(
          nil_patterns_group, dependency, all_groups, contains_checker, directory
        )
        expect(result).to be false
      end

      it "returns false when group has empty patterns array" do
        empty_patterns_group = instance_double(
          Dependabot::DependencyGroup,
          name: "empty-patterns",
          dependencies: [],
          rules: { "patterns" => [], "update-types" => ["patch"] }
        )

        result = calculator.dependency_belongs_to_more_specific_group?(
          empty_patterns_group, dependency, all_groups, contains_checker, directory
        )
        expect(result).to be false
      end
    end

    context "with complex pattern hierarchy" do
      let(:multi_wildcard_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "multi-wildcard",
          dependencies: [],
          rules: { "patterns" => ["*docker*"] }
        )
      end

      let(:prefix_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "prefix-group",
          dependencies: [],
          rules: { "patterns" => ["docker*"] }
        )
      end

      let(:complex_groups) { [generic_group, multi_wildcard_group, prefix_group, exact_group] }

      let(:complex_contains_checker) do
        proc do |group, dep, _directory|
          case group
          when generic_group
            true
          when multi_wildcard_group
            dep.name.include?("docker")
          when prefix_group
            dep.name.start_with?("docker")
          when exact_group
            dep.name == "docker-compose"
          else
            false
          end
        end
      end

      it "correctly identifies the most specific group in complex hierarchy" do
        result = calculator.dependency_belongs_to_more_specific_group?(
          multi_wildcard_group, dependency, complex_groups, complex_contains_checker, directory
        )
        expect(result).to be true

        result = calculator.dependency_belongs_to_more_specific_group?(
          prefix_group, dependency, complex_groups, complex_contains_checker, directory
        )
        expect(result).to be true

        result = calculator.dependency_belongs_to_more_specific_group?(
          exact_group, dependency, complex_groups, complex_contains_checker, directory
        )
        expect(result).to be false
      end
    end

    context "with length bonus considerations" do
      let(:short_pattern_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "short-pattern",
          dependencies: [],
          rules: { "patterns" => ["doc*"] }
        )
      end

      let(:long_pattern_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "long-pattern",
          dependencies: [],
          rules: { "patterns" => ["docker-compose*"] }
        )
      end

      let(:length_groups) { [short_pattern_group, long_pattern_group] }

      let(:length_contains_checker) do
        proc do |group, dep, _directory|
          case group
          when short_pattern_group
            dep.name.start_with?("doc")
          when long_pattern_group
            dep.name.start_with?("docker-compose")
          else
            false
          end
        end
      end

      it "prefers longer patterns over shorter ones" do
        result = calculator.dependency_belongs_to_more_specific_group?(
          short_pattern_group, dependency, length_groups, length_contains_checker, directory
        )
        expect(result).to be true
      end
    end

    context "with complex group rules" do
      let(:generic_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "generic",
          dependencies: [],
          applies_to: "version-updates",
          rules: { "patterns" => ["*"] }
        )
      end

      let(:docker_minor_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "docker-minor",
          dependencies: [],
          applies_to: "version-updates",
          rules: { "patterns" => ["docker*"], "update-types" => ["minor"] }
        )
      end

      let(:docker_exact_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "docker-compose-exact",
          dependencies: [],
          applies_to: nil,
          rules: { "patterns" => ["docker-compose"], "update-types" => ["minor"] }
        )
      end

      let(:docker_security_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "docker-security",
          dependencies: [],
          applies_to: "security-updates",
          rules: { "patterns" => ["docker*"], "update-types" => ["minor"] }
        )
      end

      let(:excluded_group) do
        instance_double(
          Dependabot::DependencyGroup,
          name: "docker-exclude-compose",
          dependencies: [],
          applies_to: "version-updates",
          rules: { "patterns" => ["docker*"], "exclude-patterns" => ["docker-compose"] }
        )
      end

      let(:all_groups) do
        [generic_group, docker_minor_group, docker_exact_group, docker_security_group, excluded_group]
      end

      let(:contains_checker) do
        proc do |group, dep, _directory|
          case group
          when generic_group then true
          when docker_minor_group, docker_security_group, excluded_group
            dep.name.start_with?("docker")
          when docker_exact_group
            dep.name == "docker-compose"
          else
            false
          end
        end
      end

      let(:docker_compose_dep) { create_dependency("docker-compose", "2.0.0") }
      let(:docker_tool_dep) { create_dependency("docker-tool", "1.0.0") }

      it "prefers the most specific allowed group for minor version updates" do
        result = calculator.dependency_belongs_to_more_specific_group?(
          generic_group,
          docker_compose_dep,
          all_groups,
          contains_checker,
          directory,
          update_type: "minor",
          applies_to: "version-updates"
        )
        expect(result).to be true # exact > prefix > generic
      end

      it "ignores more specific groups when update_type is not allowed" do
        result = calculator.dependency_belongs_to_more_specific_group?(
          generic_group,
          docker_compose_dep,
          all_groups,
          contains_checker,
          directory,
          update_type: "major",
          applies_to: "version-updates"
        )
        expect(result).to be false
      end

      it "respects applies_to when selecting security groups" do
        result = calculator.dependency_belongs_to_more_specific_group?(
          generic_group,
          docker_tool_dep,
          all_groups,
          contains_checker,
          directory,
          update_type: "minor",
          applies_to: "security-updates"
        )
        expect(result).to be true
      end

      it "respects exclusions on candidate groups" do
        result = calculator.dependency_belongs_to_more_specific_group?(
          excluded_group,
          docker_compose_dep,
          all_groups,
          contains_checker,
          directory,
          update_type: "minor",
          applies_to: "version-updates"
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
