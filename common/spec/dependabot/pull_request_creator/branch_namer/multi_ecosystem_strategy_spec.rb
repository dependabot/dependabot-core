# typed: false
# frozen_string_literal: true

require "digest"

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/dependency_group"
require "dependabot/pull_request_creator/branch_namer/multi_ecosystem_strategy"

RSpec.describe Dependabot::PullRequestCreator::BranchNamer::MultiEcosystemStrategy do
  subject(:namer) do
    described_class.new(
      dependencies: dependencies,
      files: [gemfile, package_json],
      target_branch: target_branch,
      separator: separator,
      max_length: max_length,
      includes_security_fixes: includes_security_fixes,
      multi_ecosystem_name: multi_ecosystem_name
    )
  end

  let(:multi_ecosystem_name) { "my_multi_ecosystem" }
  let(:dependencies) { [ruby_dependency, npm_dependency] }
  let(:ruby_dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      previous_version: "1.4.0",
      package_manager: "bundler",
      requirements: [],
      previous_requirements: []
    )
  end
  let(:npm_dependency) do
    Dependabot::Dependency.new(
      name: "lodash",
      version: "1.1.0",
      previous_version: "1.0.0",
      package_manager: "npm_and_yarn",
      requirements: [],
      previous_requirements: []
    )
  end

  let(:gemfile) do
    Dependabot::DependencyFile.new(
      name: "Gemfile",
      content: "anything",
      directory: "/"
    )
  end

  let(:package_json) do
    Dependabot::DependencyFile.new(
      name: "package.json",
      content: "anything",
      directory: "/"
    )
  end

  let(:max_length) { nil }
  let(:includes_security_fixes) { false }

  describe "#new_branch_name" do
    subject(:new_branch_name) { namer.new_branch_name }

    context "with defaults for separator, target branch and files in the root" do
      let(:target_branch) { "" }
      let(:separator) { "/" }

      it "returns the name of the multi-ecosystem prefixed correctly" do
        expect(namer.new_branch_name).to start_with("dependabot/my_multi_ecosystem")
      end

      it "generates a deterministic branch name for a given set of dependencies" do
        branch_name = namer.new_branch_name
        new_namer = described_class.new(
          dependencies: dependencies,
          files: [gemfile],
          target_branch: target_branch,
          separator: separator,
          includes_security_fixes: includes_security_fixes,
          multi_ecosystem_name: multi_ecosystem_name
        )
        sleep 1 # ensure the timestamp changes
        expect(new_namer.new_branch_name).to eql(branch_name)
      end

      it "generates a different branch name for a different set of dependencies for the same multi-ecosystem" do
        removed_dependency = Dependabot::Dependency.new(
          name: "old_business",
          version: "1.4.0",
          previous_version: "1.4.0",
          package_manager: "bundler",
          requirements: [],
          previous_requirements: [],
          removed: true
        )

        new_namer = described_class.new(
          dependencies: [ruby_dependency, removed_dependency],
          files: [gemfile],
          target_branch: target_branch,
          separator: separator,
          includes_security_fixes: includes_security_fixes,
          multi_ecosystem_name: multi_ecosystem_name
        )
        expect(new_namer.new_branch_name).not_to eql(namer.new_branch_name)
      end

      it "generates the same branch name regardless of the order of dependencies" do
        removed_dependency = Dependabot::Dependency.new(
          name: "old_business",
          version: "1.4.0",
          previous_version: "1.4.0",
          package_manager: "bundler",
          requirements: [],
          previous_requirements: [],
          removed: true
        )

        forward_namer = described_class.new(
          dependencies: [ruby_dependency, removed_dependency],
          files: [gemfile],
          target_branch: target_branch,
          separator: separator,
          includes_security_fixes: includes_security_fixes,
          multi_ecosystem_name: multi_ecosystem_name
        )

        backward_namer = described_class.new(
          dependencies: [removed_dependency, ruby_dependency],
          files: [gemfile],
          target_branch: target_branch,
          separator: separator,
          includes_security_fixes: includes_security_fixes,
          multi_ecosystem_name: multi_ecosystem_name
        )

        expect(forward_namer.new_branch_name).to eql(backward_namer.new_branch_name)
      end
    end

    context "with a multi-ecosystem security update" do
      let(:target_branch) { "" }
      let(:separator) { "/" }
      let(:includes_security_fixes) { true }

      it "returns the name of the security multi-ecosystem prefixed correctly" do
        expect(namer.new_branch_name).to eq("dependabot/group-security-my_multi_ecosystem-9ccbdf484a")
      end
    end

    context "with a custom separator" do
      let(:target_branch) { "" }
      let(:separator) { "_" }

      it "returns the name of the multi-ecosystem prefixed correctly" do
        expect(namer.new_branch_name).to start_with("dependabot_my_multi_ecosystem")
      end
    end

    context "with a maximum length" do
      let(:target_branch) { "" }
      let(:separator) { "/" }

      context "with a maximum length longer than branch name" do
        let(:max_length) { 50 }
        let(:multi_ecosystem_name) { "mitt_multi_ecosystem_longer" }

        it { is_expected.to eq("dependabot/mitt_multi_ecosystem_longer-9ccbdf484a") }
        its(:length) { is_expected.to eq(49) }
      end

      context "with a maximum length shorter than branch name" do
        let(:multi_ecosystem_name) { "business-and-work-and-desks-and-tables-and-chairs" }
        let(:sha1_digest) { Digest::SHA1.hexdigest("dependabot/#{multi_ecosystem_name}-9ccbdf484a") }

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

    context "when dealing with the files targeting a branch" do
      let(:target_branch) { "develop" }
      let(:separator) { "/" }

      it "returns the name of the multi-ecosystem prefixed correctly" do
        expect(namer.new_branch_name).to start_with("dependabot/develop/my_multi_ecosystem-9ccbdf484a")
      end
    end

    context "when dealing with files in a multi-ecosystem targeting a branch" do
      let(:target_branch) { "develop" }
      let(:separator) { "_" }

      it "returns the name of the multi-ecosystem prefixed correctly" do
        expect(namer.new_branch_name).to start_with("dependabot_develop_my_multi_ecosystem-9ccbdf484a")
      end
    end
  end
end
