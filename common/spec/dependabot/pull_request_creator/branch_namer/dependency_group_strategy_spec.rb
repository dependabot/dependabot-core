# frozen_string_literal: true

require "digest"

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/dependency_group"
require "dependabot/pull_request_creator/branch_namer/dependency_group_strategy"

RSpec.describe Dependabot::PullRequestCreator::BranchNamer::DependencyGroupStrategy do
  subject(:namer) do
    described_class.new(
      dependencies: dependencies,
      files: [gemfile],
      target_branch: target_branch,
      separator: separator,
      dependency_group: dependency_group,
      max_length: max_length
    )
  end

  let(:dependencies) { [dependency] }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      previous_version: "1.4.0",
      package_manager: "bundler",
      requirements: {},
      previous_requirements: {}
    )
  end
  let(:gemfile) do
    Dependabot::DependencyFile.new(
      name: "Gemfile",
      content: "anything",
      directory: directory
    )
  end

  let(:dependency_group) do
    Dependabot::DependencyGroup.new(name: "my-dependency-group", rules: { patterns: ["*"] })
  end
  let(:max_length) { nil }

  describe "#new_branch_name" do
    subject(:new_branch_name) { namer.new_branch_name }

    context "with defaults for separator, target branch and files in the root directory" do
      let(:directory) { "/" }
      let(:target_branch) { nil }
      let(:separator) { "/" }

      it "returns the name of the dependency group prefixed correctly" do
        expect(namer.new_branch_name).to start_with("dependabot/bundler/my-dependency-group")
      end

      it "generates a deterministic branch name for a given set of dependencies" do
        branch_name = namer.new_branch_name
        new_namer = described_class.new(
          dependencies: dependencies,
          files: [gemfile],
          target_branch: target_branch,
          separator: separator,
          dependency_group: dependency_group
        )
        sleep 1 # ensure the timestamp changes
        expect(new_namer.new_branch_name).to eql(branch_name)
      end

      it "generates a different branch name for a different set of dependencies for the same group" do
        removed_dependency = Dependabot::Dependency.new(
          name: "old_business",
          version: "1.4.0",
          previous_version: "1.4.0",
          package_manager: "bundler",
          requirements: {},
          previous_requirements: {},
          removed: true
        )

        new_namer = described_class.new(
          dependencies: [dependency, removed_dependency],
          files: [gemfile],
          target_branch: target_branch,
          separator: separator,
          dependency_group: dependency_group
        )
        expect(new_namer.new_branch_name).not_to eql(namer.new_branch_name)
      end

      it "generates the same branch name regardless of the order of dependencies" do
        removed_dependency = Dependabot::Dependency.new(
          name: "old_business",
          version: "1.4.0",
          previous_version: "1.4.0",
          package_manager: "bundler",
          requirements: {},
          previous_requirements: {},
          removed: true
        )

        forward_namer = described_class.new(
          dependencies: [dependency, removed_dependency],
          files: [gemfile],
          target_branch: target_branch,
          separator: separator,
          dependency_group: dependency_group
        )

        backward_namer = described_class.new(
          dependencies: [removed_dependency, dependency],
          files: [gemfile],
          target_branch: target_branch,
          separator: separator,
          dependency_group: dependency_group
        )

        expect(forward_namer.new_branch_name).to eql(backward_namer.new_branch_name)
      end
    end

    context "with a custom separator" do
      let(:directory) { "/" }
      let(:target_branch) { nil }
      let(:separator) { "_" }

      it "returns the name of the dependency group prefixed correctly" do
        expect(namer.new_branch_name).to start_with("dependabot_bundler_my-dependency-group")
      end
    end

    context "with a maximum length" do
      let(:directory) { "/" }
      let(:target_branch) { nil }
      let(:separator) { "/" }

      context "with a maximum length longer than branch name" do
        let(:max_length) { 50 }

        it { is_expected.to eq("dependabot/bundler/my-dependency-group-b8d660191d") }
        its(:length) { is_expected.to eq(49) }
      end

      context "with a maximum length shorter than branch name" do
        let(:dependency_group) do
          Dependabot::DependencyGroup.new(
            name: "business-and-work-and-desks-and-tables-and-chairs",
            rules: { patterns: ["*"] }
          )
        end

        let(:sha1_digest) { Digest::SHA1.hexdigest("dependabot/bundler/#{dependency_group.name}-b8d660191d") }

        context "with a maximum length longer than sha1 length" do
          let(:max_length) { 50 }

          it { is_expected.to eq("dependabot#{sha1_digest}") }
          its(:length) { is_expected.to eq(50) }
        end

        context "with a maximum length equal than sha1 length" do
          let(:max_length) { 40 }

          it { is_expected.to eq(sha1_digest) }
          its(:length) { is_expected.to eq(40) }
        end

        context "with a maximum length shorter than sha1 length" do
          let(:max_length) { 20 }

          it { is_expected.to eq(sha1_digest[0...20]) }
          its(:length) { is_expected.to eq(20) }
        end
      end
    end

    context "for files in a non-root directory" do
      let(:directory) { "rails app/" } # let's make sure we deal with spaces too
      let(:target_branch) { nil }
      let(:separator) { "/" }

      it "returns the name of the dependency group prefixed correctly" do
        expect(namer.new_branch_name).to start_with("dependabot/bundler/rails-app/my-dependency-group")
      end
    end

    context "targeting a branch" do
      let(:directory) { "/" }
      let(:target_branch) { "develop" }
      let(:separator) { "/" }

      it "returns the name of the dependency group prefixed correctly" do
        expect(namer.new_branch_name).to start_with("dependabot/bundler/develop/my-dependency-group")
      end
    end

    context "for files in a non-root directory targeting a branch" do
      let(:directory) { "rails-app/" }
      let(:target_branch) { "develop" }
      let(:separator) { "_" }

      it "returns the name of the dependency group prefixed correctly" do
        expect(namer.new_branch_name).to start_with("dependabot_bundler_rails-app_develop_my-dependency-group")
      end
    end
  end
end
