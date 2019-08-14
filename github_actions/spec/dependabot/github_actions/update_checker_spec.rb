# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/github_actions/update_checker"
require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::GithubActions::UpdateChecker do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      credentials: credentials,
      ignored_versions: ignored_versions
    )
  end
  let(:ignored_versions) { [] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: nil,
      requirements: [{
        requirement: nil,
        groups: [],
        file: ".github/workflows/workflow.yml",
        source: dependency_source,
        metadata: { declaration_string: "actions/setup-node@master" }
      }],
      package_manager: "github_actions"
    )
  end
  let(:dependency_name) { "actions/setup-node" }
  let(:dependency_source) do
    {
      type: "git",
      url: "https://github.com/actions/setup-node",
      ref: reference,
      branch: nil
    }
  end
  let(:reference) { "master" }
  let(:service_pack_url) do
    "https://github.com/actions/setup-node.git/info/refs"\
    "?service=git-upload-pack"
  end
  before do
    stub_request(:get, service_pack_url).
      to_return(
        status: 200,
        body: fixture("git", "upload_packs", upload_pack_fixture),
        headers: {
          "content-type" => "application/x-git-upload-pack-advertisement"
        }
      )
  end
  let(:upload_pack_fixture) { "setup-node" }

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }

    context "given a dependency with a branch reference" do
      let(:reference) { "master" }
      it { is_expected.to be_falsey }
    end

    context "given a dependency with a tag reference" do
      let(:reference) { "v1.0.1" }
      it { is_expected.to be_truthy }

      context "that is up-to-date" do
        let(:reference) { "v1.1.0" }
        it { is_expected.to be_falsey }
      end
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    context "given a dependency with a branch reference" do
      let(:reference) { "master" }
      it { is_expected.to eq("d963e800e3592dd31d6c76252092562d0bc7a3ba") }
    end

    context "given a dependency with a tag reference" do
      let(:reference) { "v1.0.1" }
      it { is_expected.to eq("5273d0df9c603edc4284ac8402cf650b4f1f6686") }
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }

    before { allow(checker).to receive(:latest_version).and_return("delegate") }
    it { is_expected.to eq("delegate") }
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements }

    context "given a dependency with a branch reference" do
      let(:reference) { "master" }
      it { is_expected.to eq(dependency.requirements) }
    end

    context "given a dependency with a tag reference" do
      let(:reference) { "v1.0.1" }
      let(:expected_requirements) do
        [{
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          source: {
            type: "git",
            url: "https://github.com/actions/setup-node",
            ref: "v1.1.0",
            branch: nil
          },
          metadata: { declaration_string: "actions/setup-node@master" }
        }]
      end

      it { is_expected.to eq(expected_requirements) }
    end
  end
end
