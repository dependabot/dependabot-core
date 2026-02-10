# typed: false
# frozen_string_literal: true

require "spec_helper"
require "support/dependency_file_helpers"

require "dependabot/dependency"
require "dependabot/dependency_group_engine"
require "dependabot/dependency_snapshot"
require "dependabot/job"
require "dependabot/experiments"

RSpec.describe Dependabot::DependencyGroupEngine do
  include DependencyFileHelpers

  let(:dependency_group_engine) { described_class.from_job_config(job: job) }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/",
      branch: "master"
    )
  end
  let(:security_updates_only) { false }
  let(:dependencies) { nil }
  let(:job) do
    instance_double(
      Dependabot::Job,
      dependency_groups: dependency_groups_config,
      source: source,
      dependencies: dependencies,
      security_updates_only?: security_updates_only
    )
  end

  let(:dummy_pkg_a) do
    Dependabot::Dependency.new(
      name: "dummy-pkg-a",
      package_manager: "bundler",
      version: "1.1.0",
      requirements: [
        {
          file: "Gemfile",
          requirement: "~> 1.1.0",
          groups: ["default"],
          source: nil
        }
      ],
      directory: "/"
    )
  end

  let(:dummy_pkg_b) do
    Dependabot::Dependency.new(
      name: "dummy-pkg-b",
      package_manager: "bundler",
      version: "1.1.0",
      requirements: [
        {
          file: "Gemfile",
          requirement: "~> 1.1.0",
          groups: ["default"],
          source: nil
        }
      ],
      directory: "/"
    )
  end

  let(:dummy_pkg_c) do
    Dependabot::Dependency.new(
      name: "dummy-pkg-c",
      package_manager: "bundler",
      version: "1.1.0",
      requirements: [
        {
          file: "Gemfile",
          requirement: "~> 1.1.0",
          groups: ["default"],
          source: nil
        }
      ],
      directory: "/"
    )
  end

  let(:ungrouped_pkg) do
    Dependabot::Dependency.new(
      name: "ungrouped_pkg",
      package_manager: "bundler",
      version: "1.1.0",
      requirements: [
        {
          file: "Gemfile",
          requirement: "~> 1.1.0",
          groups: ["default"],
          source: nil
        }
      ],
      directory: "/"
    )
  end

  context "when a job has grouped configured, and it's a version update" do
    let(:dependency_groups_config) do
      [
        {
          "name" => "group-a",
          "rules" => {
            "patterns" => ["dummy-pkg-*"],
            "exclude-patterns" => ["dummy-pkg-b"]
          }
        },
        {
          "name" => "group-b",
          "applies-to" => "security-updates",
          "rules" => {
            "patterns" => %w(dummy-pkg-b dummy-pkg-c)
          }
        }
      ]
    end

    describe "::from_job_config" do
      it "filters out the security update" do
        expect(dependency_group_engine.dependency_groups.length).to be(1)
        expect(dependency_group_engine.dependency_groups.map(&:name)).to eql(%w(group-a))
      end
    end

    context "when it's a security update" do
      let(:security_updates_only) { true }
      let(:dependencies) { %w(dummy-pkg-a dummy-pkg-b dummy-pkg-c ungrouped_pkg) }

      describe "::from_job_config" do
        it "filters out the version update" do
          expect(dependency_group_engine.dependency_groups.length).to be(1)
          expect(dependency_group_engine.dependency_groups.map(&:name)).to eql(%w(group-b))
        end
      end
    end
  end

  context "when a job has groups configured" do
    let(:dependency_groups_config) do
      [
        {
          "name" => "group-a",
          "rules" => {
            "patterns" => ["dummy-pkg-*"],
            "exclude-patterns" => ["dummy-pkg-b"]
          }
        },
        {
          "name" => "group-b",
          "rules" => {
            "patterns" => %w(dummy-pkg-b dummy-pkg-c)
          }
        }
      ]
    end

    describe "::from_job_config" do
      it "registers the dependency groups" do
        expect(dependency_group_engine.dependency_groups.length).to be(2)
        expect(dependency_group_engine.dependency_groups.map(&:name)).to eql(%w(group-a group-b))
        expect(dependency_group_engine.dependency_groups.map(&:dependencies)).to all(be_empty)
      end
    end

    describe "#find_group" do
      it "retrieves a defined group by name" do
        group_a = dependency_group_engine.find_group(name: "group-a")
        expect(group_a.rules).to eql(
          {
            "patterns" => ["dummy-pkg-*"],
            "exclude-patterns" => ["dummy-pkg-b"]
          }
        )
      end

      it "returns nil if the group does not exist" do
        expect(dependency_group_engine.find_group(name: "no-such-thing")).to be_nil
      end
    end

    describe "#assign_to_groups!" do
      context "when all groups have at least one dependency that matches" do
        let(:dependencies) { [dummy_pkg_a, dummy_pkg_b, dummy_pkg_c, ungrouped_pkg] }

        before do
          dependency_group_engine.assign_to_groups!(dependencies: dependencies)
        end

        it "adds dependencies to every group they match" do
          group_a = dependency_group_engine.find_group(name: "group-a")
          expect(group_a.dependencies).to eql([dummy_pkg_a, dummy_pkg_c])

          group_b = dependency_group_engine.find_group(name: "group-b")
          expect(group_b.dependencies).to eql([dummy_pkg_b, dummy_pkg_c])
        end

        it "keeps a list of any dependencies that do not match any groups" do
          expect(dependency_group_engine.ungrouped_dependencies).to eql([ungrouped_pkg])
        end
      end

      context "when one group has no matching dependencies" do
        let(:dependencies) { [dummy_pkg_a] }

        it "warns that the group is misconfigured" do
          expect(Dependabot.logger).to receive(:warn).with(
            <<~WARN
              Please check your configuration as there are groups where no dependencies match:
              - group-b

              This can happen if:
              - the group's 'pattern' rules are misspelled
              - your configuration's 'allow' rules do not permit any of the dependencies that match the group
              - the dependencies that match the group rules have been removed from your project
            WARN
          )

          dependency_group_engine.assign_to_groups!(dependencies: dependencies)
        end
      end

      context "when no groups have any matching dependencies" do
        let(:dependencies) { [ungrouped_pkg] }

        it "warns that the groups are misconfigured" do
          expect(Dependabot.logger).to receive(:warn).with(
            <<~WARN
              Please check your configuration as there are groups where no dependencies match:
              - group-a
              - group-b

              This can happen if:
              - the group's 'pattern' rules are misspelled
              - your configuration's 'allow' rules do not permit any of the dependencies that match the group
              - the dependencies that match the group rules have been removed from your project
            WARN
          )

          dependency_group_engine.assign_to_groups!(dependencies: dependencies)
        end
      end
    end

    context "with group membership enforcement experiment" do
      let(:dependency_groups_config) do
        [
          {
            "name" => "generic-group",
            "rules" => {
              "patterns" => ["*"]
            }
          },
          {
            "name" => "specific-group",
            "rules" => {
              "patterns" => ["dummy-pkg-*"]
            }
          },
          {
            "name" => "very-specific-group",
            "rules" => {
              "patterns" => ["dummy-pkg-a"]
            }
          }
        ]
      end

      let(:dependencies) { [dummy_pkg_a, dummy_pkg_b, ungrouped_pkg] }

      before do
        allow(Dependabot::Experiments).to receive(:enabled?).and_call_original
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_membership_enforcement)
          .and_return(experiment_enabled)
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_by_dependency_name)
          .and_return(false)
      end

      context "when experiment is enabled" do
        let(:experiment_enabled) { true }

        before do
          dependency_group_engine.assign_to_groups!(dependencies: dependencies)
        end

        it "assigns dependencies to most specific matching groups only" do
          generic_group = dependency_group_engine.find_group(name: "generic-group")
          specific_group = dependency_group_engine.find_group(name: "specific-group")
          very_specific_group = dependency_group_engine.find_group(name: "very-specific-group")

          # dummy-pkg-a should only be in the most specific group (very-specific-group)
          expect(very_specific_group.dependencies).to include(dummy_pkg_a)
          expect(specific_group.dependencies).not_to include(dummy_pkg_a)
          expect(generic_group.dependencies).not_to include(dummy_pkg_a)

          # dummy-pkg-b should be in specific-group (most specific match)
          expect(specific_group.dependencies).to include(dummy_pkg_b)
          expect(generic_group.dependencies).not_to include(dummy_pkg_b)

          # ungrouped_pkg should be in generic-group (only match)
          expect(generic_group.dependencies).to include(ungrouped_pkg)
        end

        it "keeps dependencies ungrouped if they don't match any patterns" do
          # All dependencies should be grouped in this test case
          expect(dependency_group_engine.ungrouped_dependencies).to be_empty
        end
      end

      context "when experiment is disabled" do
        let(:experiment_enabled) { false }

        before do
          dependency_group_engine.assign_to_groups!(dependencies: dependencies)
        end

        it "assigns dependencies to all matching groups (legacy behavior)" do
          generic_group = dependency_group_engine.find_group(name: "generic-group")
          specific_group = dependency_group_engine.find_group(name: "specific-group")
          very_specific_group = dependency_group_engine.find_group(name: "very-specific-group")

          # dummy-pkg-a should be in all matching groups
          expect(very_specific_group.dependencies).to include(dummy_pkg_a)
          expect(specific_group.dependencies).to include(dummy_pkg_a)
          expect(generic_group.dependencies).to include(dummy_pkg_a)

          # dummy-pkg-b should be in matching groups
          expect(specific_group.dependencies).to include(dummy_pkg_b)
          expect(generic_group.dependencies).to include(dummy_pkg_b)

          # ungrouped_pkg should be in generic-group
          expect(generic_group.dependencies).to include(ungrouped_pkg)
        end
      end

      describe "#should_skip_due_to_specificity?" do
        let(:generic_group) { dependency_group_engine.find_group(name: "generic-group") }
        let(:specific_group) { dependency_group_engine.find_group(name: "specific-group") }
        let(:very_specific_group) { dependency_group_engine.find_group(name: "very-specific-group") }
        let(:specificity_calculator) { Dependabot::Updater::PatternSpecificityCalculator.new }

        context "when experiment is enabled" do
          let(:experiment_enabled) { true }

          it "returns true when dependency belongs to more specific group" do
            # dummy-pkg-a belongs to very-specific-group, so should skip generic and specific groups
            expect(
              dependency_group_engine.send(
                :should_skip_due_to_specificity?,
                generic_group,
                dummy_pkg_a,
                specificity_calculator
              )
            ).to be(true)
            expect(
              dependency_group_engine.send(
                :should_skip_due_to_specificity?,
                specific_group,
                dummy_pkg_a,
                specificity_calculator
              )
            ).to be(true)
          end

          it "returns false when dependency belongs to most specific group" do
            # dummy-pkg-a in very-specific-group (most specific) should not be skipped
            expect(
              dependency_group_engine.send(
                :should_skip_due_to_specificity?,
                very_specific_group,
                dummy_pkg_a,
                specificity_calculator
              )
            ).to be(false)
          end

          it "returns false when no more specific group exists" do
            # ungrouped_pkg only matches generic-group, so should not be skipped
            expect(
              dependency_group_engine.send(
                :should_skip_due_to_specificity?,
                generic_group,
                ungrouped_pkg,
                specificity_calculator
              )
            ).to be(false)
          end
        end

        context "when experiment is disabled" do
          let(:experiment_enabled) { false }

          it "always returns false regardless of specificity" do
            expect(
              dependency_group_engine.send(
                :should_skip_due_to_specificity?,
                generic_group,
                dummy_pkg_a,
                specificity_calculator
              )
            ).to be(false)
            expect(
              dependency_group_engine.send(
                :should_skip_due_to_specificity?,
                specific_group,
                dummy_pkg_a,
                specificity_calculator
              )
            ).to be(false)
            expect(
              dependency_group_engine.send(
                :should_skip_due_to_specificity?,
                very_specific_group,
                dummy_pkg_a,
                specificity_calculator
              )
            ).to be(false)
          end
        end
      end
    end

    context "when a job has no groups configured" do
      let(:dependency_groups_config) { [] }

      describe "::from_job_config" do
        it "registers no dependency groups" do
          expect(dependency_group_engine.dependency_groups).to be_empty
        end
      end

      describe "#assign_to_groups!" do
        let(:dummy_pkg_a) do
          Dependabot::Dependency.new(
            name: "dummy-pkg-a",
            package_manager: "bundler",
            version: "1.1.0",
            requirements: [
              {
                file: "Gemfile",
                requirement: "~> 1.1.0",
                groups: ["default"],
                source: nil
              }
            ],
            directory: "/"
          )
        end

        let(:dummy_pkg_b) do
          Dependabot::Dependency.new(
            name: "dummy-pkg-b",
            package_manager: "bundler",
            version: "1.1.0",
            requirements: [
              {
                file: "Gemfile",
                requirement: "~> 1.1.0",
                groups: ["default"],
                source: nil
              }
            ],
            directory: "/"
          )
        end

        let(:dependencies) { [dummy_pkg_a, dummy_pkg_b] }

        before do
          dependency_group_engine.assign_to_groups!(dependencies: dependencies)
        end

        it "lists all dependencies as ungrouped" do
          expect(dependency_group_engine.ungrouped_dependencies).to eql(dependencies)
        end
      end
    end
  end

  describe "::from_job_config validation" do
    let(:dependency_groups_config) do
      [
        {
          "name" => "test-group",
          "rules" => {
            "dependency-type" => "production"
          }
        }
      ]
    end

    context "when dependency-type is used with a supported package manager" do
      %w(bundler composer hex maven npm_and_yarn pip uv).each do |package_manager|
        context "with #{package_manager}" do
          let(:job) do
            instance_double(
              Dependabot::Job,
              dependency_groups: dependency_groups_config,
              source: source,
              dependencies: nil,
              security_updates_only?: false,
              package_manager: package_manager
            )
          end

          it "does not log a warning" do
            expect(Dependabot.logger).not_to receive(:warn)
            dependency_group_engine
          end
        end
      end
    end

    context "when dependency-type is used with an unsupported package manager" do
      %w(gradle go_modules cargo docker terraform).each do |package_manager|
        context "with #{package_manager}" do
          let(:job) do
            instance_double(
              Dependabot::Job,
              dependency_groups: dependency_groups_config,
              source: source,
              dependencies: nil,
              security_updates_only?: false,
              package_manager: package_manager
            )
          end

          it "logs a warning about unsupported option" do
            expect(Dependabot.logger).to receive(:warn).with(
              a_string_matching(
                /The 'dependency-type' option is not supported for the '#{package_manager}' package manager/
              )
            )
            dependency_group_engine
          end

          it "includes the group name in the warning message" do
            expect(Dependabot.logger).to receive(:warn).with(
              a_string_matching(/Affected groups: test-group/)
            )
            dependency_group_engine
          end

          it "lists supported package managers in the warning message" do
            expect(Dependabot.logger).to receive(:warn).with(
              a_string_matching(/bundler, composer, hex, maven, npm_and_yarn, pip, uv/)
            )
            dependency_group_engine
          end
        end
      end
    end

    context "when multiple groups use dependency-type with an unsupported package manager" do
      let(:dependency_groups_config) do
        [
          {
            "name" => "group-one",
            "rules" => {
              "dependency-type" => "production"
            }
          },
          {
            "name" => "group-two",
            "rules" => {
              "dependency-type" => "development"
            }
          }
        ]
      end

      let(:job) do
        instance_double(
          Dependabot::Job,
          dependency_groups: dependency_groups_config,
          source: source,
          dependencies: nil,
          security_updates_only?: false,
          package_manager: "gradle"
        )
      end

      it "logs a warning mentioning all affected groups" do
        expect(Dependabot.logger).to receive(:warn).with(
          a_string_matching(/Affected groups: group-one, group-two/)
        )
        dependency_group_engine
      end
    end

    context "when groups don't use dependency-type with an unsupported package manager" do
      let(:dependency_groups_config) do
        [
          {
            "name" => "test-group",
            "rules" => {
              "patterns" => ["dummy-*"]
            }
          }
        ]
      end

      let(:job) do
        instance_double(
          Dependabot::Job,
          dependency_groups: dependency_groups_config,
          source: source,
          dependencies: nil,
          security_updates_only?: false,
          package_manager: "gradle"
        )
      end

      it "does not log a warning" do
        expect(Dependabot.logger).not_to receive(:warn)
        dependency_group_engine
      end
    end
  end

  context "when a group has group-by: dependency-name configured" do
    let(:dummy_pkg_a_dir1) do
      Dependabot::Dependency.new(
        name: "dummy-pkg-a",
        package_manager: "bundler",
        version: "1.1.0",
        requirements: [
          {
            file: "packages/app1/Gemfile",
            requirement: "~> 1.1.0",
            groups: ["default"],
            source: nil
          }
        ],
        directory: "/packages/app1"
      )
    end

    let(:dummy_pkg_a_dir2) do
      Dependabot::Dependency.new(
        name: "dummy-pkg-a",
        package_manager: "bundler",
        version: "1.0.0",
        requirements: [
          {
            file: "packages/app2/Gemfile",
            requirement: "~> 1.0.0",
            groups: ["default"],
            source: nil
          }
        ],
        directory: "/packages/app2"
      )
    end

    let(:dummy_pkg_b_dir1) do
      Dependabot::Dependency.new(
        name: "dummy-pkg-b",
        package_manager: "bundler",
        version: "2.0.0",
        requirements: [
          {
            file: "packages/app1/Gemfile",
            requirement: "~> 2.0.0",
            groups: ["default"],
            source: nil
          }
        ],
        directory: "/packages/app1"
      )
    end

    let(:other_pkg) do
      Dependabot::Dependency.new(
        name: "other-pkg",
        package_manager: "bundler",
        version: "1.0.0",
        requirements: [
          {
            file: "Gemfile",
            requirement: "~> 1.0.0",
            groups: ["default"],
            source: nil
          }
        ],
        directory: "/"
      )
    end

    let(:dependency_groups_config) do
      [
        {
          "name" => "monorepo-deps",
          "rules" => {
            "patterns" => ["dummy-pkg-*"],
            "group-by" => "dependency-name"
          }
        }
      ]
    end

    let(:job) do
      instance_double(
        Dependabot::Job,
        dependency_groups: dependency_groups_config,
        source: source,
        dependencies: nil,
        security_updates_only?: false,
        package_manager: "bundler"
      )
    end

    before do
      allow(Dependabot::Experiments).to receive(:enabled?).and_call_original
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:group_by_dependency_name)
        .and_return(true)
      allow(Dependabot::Experiments).to receive(:enabled?)
        .with(:group_membership_enforcement)
        .and_return(false)
    end

    describe "::from_job_config" do
      it "creates groups with group_by attribute set" do
        expect(dependency_group_engine.dependency_groups.length).to eq(1)
        parent_group = dependency_group_engine.find_group(name: "monorepo-deps")
        expect(parent_group.group_by).to eq("dependency-name")
      end
    end

    describe "#assign_to_groups!" do
      let(:dependencies) { [dummy_pkg_a_dir1, dummy_pkg_a_dir2, dummy_pkg_b_dir1, other_pkg] }

      before do
        dependency_group_engine.assign_to_groups!(dependencies: dependencies)
      end

      it "creates subgroups for each unique dependency name" do
        subgroup_a = dependency_group_engine.find_group(name: "monorepo-deps/dummy-pkg-a")
        subgroup_b = dependency_group_engine.find_group(name: "monorepo-deps/dummy-pkg-b")

        expect(subgroup_a).not_to be_nil
        expect(subgroup_b).not_to be_nil
      end

      it "assigns all instances of a dependency across directories to its subgroup" do
        subgroup_a = dependency_group_engine.find_group(name: "monorepo-deps/dummy-pkg-a")

        expect(subgroup_a.dependencies).to contain_exactly(dummy_pkg_a_dir1, dummy_pkg_a_dir2)
      end

      it "leaves the parent group with no dependencies" do
        parent_group = dependency_group_engine.find_group(name: "monorepo-deps")

        expect(parent_group.dependencies).to be_empty
      end

      it "marks dependencies not matching the parent group pattern as ungrouped" do
        expect(dependency_group_engine.ungrouped_dependencies).to contain_exactly(other_pkg)
      end

      it "does not warn about the empty parent group" do
        # The parent group being empty is expected behavior, not a misconfiguration
        expect(Dependabot.logger).not_to receive(:warn)
        dependency_group_engine.assign_to_groups!(dependencies: dependencies)
      end

      it "sets subgroup rules to target the specific dependency" do
        subgroup_a = dependency_group_engine.find_group(name: "monorepo-deps/dummy-pkg-a")

        expect(subgroup_a.rules["patterns"]).to eq(["dummy-pkg-a"])
      end

      it "preserves parent group applies_to in subgroups" do
        subgroup_a = dependency_group_engine.find_group(name: "monorepo-deps/dummy-pkg-a")

        expect(subgroup_a.applies_to).to eq("version-updates")
      end

      it "does not set group_by on subgroups to prevent infinite recursion" do
        subgroup_a = dependency_group_engine.find_group(name: "monorepo-deps/dummy-pkg-a")

        expect(subgroup_a.group_by).to be_nil
        expect(subgroup_a.group_by_dependency_name?).to be(false)
      end
    end

    context "when the feature flag is disabled" do
      before do
        allow(Dependabot::Experiments).to receive(:enabled?).and_call_original
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_by_dependency_name)
          .and_return(false)
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_membership_enforcement)
          .and_return(false)
      end

      describe "#assign_to_groups!" do
        let(:dependencies) { [dummy_pkg_a_dir1, dummy_pkg_a_dir2, dummy_pkg_b_dir1] }

        before do
          dependency_group_engine.assign_to_groups!(dependencies: dependencies)
        end

        it "treats the group as a regular group and assigns dependencies directly" do
          parent_group = dependency_group_engine.find_group(name: "monorepo-deps")

          # When flag is disabled, group_by_dependency_name? returns false
          # so the group is treated as a regular group
          expect(parent_group.dependencies).to contain_exactly(
            dummy_pkg_a_dir1, dummy_pkg_a_dir2, dummy_pkg_b_dir1
          )
        end

        it "does not create subgroups" do
          subgroup_a = dependency_group_engine.find_group(name: "monorepo-deps/dummy-pkg-a")
          expect(subgroup_a).to be_nil
        end
      end
    end

    context "when there are mixed regular groups and group-by groups" do
      let(:dependency_groups_config) do
        [
          {
            "name" => "monorepo-deps",
            "rules" => {
              "patterns" => ["dummy-pkg-*"],
              "group-by" => "dependency-name"
            }
          },
          {
            "name" => "other-deps",
            "rules" => {
              "patterns" => ["other-*"]
            }
          }
        ]
      end

      before do
        allow(Dependabot::Experiments).to receive(:enabled?).and_call_original
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_by_dependency_name)
          .and_return(true)
        allow(Dependabot::Experiments).to receive(:enabled?)
          .with(:group_membership_enforcement)
          .and_return(false)
      end

      describe "#assign_to_groups!" do
        let(:dependencies) { [dummy_pkg_a_dir1, dummy_pkg_a_dir2, other_pkg] }

        before do
          dependency_group_engine.assign_to_groups!(dependencies: dependencies)
        end

        it "handles both group types correctly" do
          # Regular group should have its dependencies
          other_group = dependency_group_engine.find_group(name: "other-deps")
          expect(other_group.dependencies).to contain_exactly(other_pkg)

          # Subgroup should be created for the group-by group
          subgroup_a = dependency_group_engine.find_group(name: "monorepo-deps/dummy-pkg-a")
          expect(subgroup_a.dependencies).to contain_exactly(dummy_pkg_a_dir1, dummy_pkg_a_dir2)
        end

        it "does not mark dependencies as ungrouped if they match any group" do
          expect(dependency_group_engine.ungrouped_dependencies).to be_empty
        end
      end
    end
  end
end
