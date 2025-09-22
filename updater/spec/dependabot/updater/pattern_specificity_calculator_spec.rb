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
