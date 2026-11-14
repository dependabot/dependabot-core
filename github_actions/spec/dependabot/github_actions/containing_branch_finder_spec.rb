# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/github_actions/containing_branch_finder"

RSpec.describe Dependabot::GithubActions::ContainingBranchFinder do
  let(:sha) { "97a0fba1372883ab732affbe8f94b823f91727db" }

  before do
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command)
      .with("git branch --remotes --contains #{sha}", any_args)
      .and_return(branches)
  end

  describe ".find" do
    subject(:branch) { described_class.find(sha) }

    context "when the commit is on one branch" do
      let(:branches) { "  origin/releases/v1\n" }

      it { is_expected.to eq("releases/v1") }
    end

    context "when the commit is on several branches, including the default one" do
      let(:branches) { "  origin/HEAD -> origin/main\n  origin/main\n  origin/v3/node20\n" }

      it { is_expected.to eq("main") }
    end

    context "when the commit is on several branches and the default one is not among them" do
      let(:branches) { "  origin/v3/node20\n  origin/v3/v3.2.2\n  origin/v3/v3.2.2-node20\n" }

      it "returns no branch instead of raising" do
        expect(branch).to be_nil
      end
    end

    context "when no branch contains the commit" do
      let(:branches) { "" }

      it { is_expected.to be_nil }
    end
  end
end
