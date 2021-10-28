# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pull_request_updater"

RSpec.describe Dependabot::PullRequestUpdater do
  subject(:updater) do
    described_class.new(
      source: source,
      base_commit: base_commit,
      old_commit: old_commit,
      files: files,
      credentials: credentials,
      pull_request_number: pull_request_number,
      provider_metadata: provider_metadata
    )
  end

  let(:source) { Dependabot::Source.new(provider: "github", repo: "gc/bp") }
  let(:files) { [] }
  let(:base_commit) { "basecommitsha" }
  let(:old_commit) { "oldcommitsha" }
  let(:pull_request_number) { 1 }
  let(:credentials) { [] }
  let(:target_project_id) { 1 }
  let(:provider_metadata) { {} }

  describe "#update" do
    context "with a GitHub source" do
      let(:source) { Dependabot::Source.new(provider: "github", repo: "gc/bp") }
      let(:dummy_updater) { instance_double(described_class::Github) }

      it "delegates to PullRequestUpdater::Github with correct params" do
        expect(described_class::Github).
          to receive(:new).
          with(
            source: source,
            base_commit: base_commit,
            old_commit: old_commit,
            files: files,
            credentials: credentials,
            pull_request_number: pull_request_number,
            author_details: nil,
            signature_key: nil
          ).and_return(dummy_updater)
        expect(dummy_updater).to receive(:update)
        updater.update
      end
    end

    context "with a Gitlab source" do
      let(:source) { Dependabot::Source.new(provider: "gitlab", repo: "gc/bp") }
      let(:dummy_updater) { instance_double(described_class::Gitlab) }
      let(:provider_metadata) { { target_project_id: 1 } }

      it "delegates to PullRequestUpdater::Gitlab with correct params" do
        expect(described_class::Gitlab).
          to receive(:new).
          with(
            source: source,
            base_commit: base_commit,
            old_commit: old_commit,
            files: files,
            credentials: credentials,
            pull_request_number: pull_request_number,
            target_project_id: provider_metadata[:target_project_id]
          ).and_return(dummy_updater)
        expect(dummy_updater).to receive(:update)
        updater.update
      end
    end
    context "with unsupported source" do
      let(:source) do
        Dependabot::Source.new(provider: "unknown", repo: "gc/bp")
      end

      it "raise an error" do
        expect { updater.update }.
          to raise_error(RuntimeError, "Unexpected provider 'unknown'")
      end
    end
  end
end
