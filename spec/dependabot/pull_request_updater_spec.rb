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
      files: files,
      credentials: credentials,
      pull_request_number: pull_request_number
    )
  end

  let(:source) { Dependabot::Source.new(provider: "github", repo: "gc/bp") }
  let(:files) { [] }
  let(:base_commit) { "basecommitsha" }
  let(:pull_request_number) { 1 }
  let(:credentials) { [] }

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
  end
end
