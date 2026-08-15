# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/pull_request_creator/codecommit"

RSpec.describe Dependabot::PullRequestCreator::Codecommit do
  subject(:creator) do
    described_class.new(
      source: source,
      branch_name: branch_name,
      base_commit: "base",
      credentials: [],
      files: [dependency_file],
      commit_message: "Bump dependency",
      pr_description: "PR description",
      pr_name: "PR name",
      author_details: nil,
      labeler: nil,
      require_up_to_date_base: false
    )
  end

  let(:source) do
    Dependabot::Source.new(
      provider: "codecommit",
      repo: "gocardless",
      branch: "main"
    )
  end
  let(:branch_name) { "dependabot/bundler/business-1.5.0" }
  let(:dependency_file) do
    Dependabot::DependencyFile.new(name: "Gemfile", content: "gem \"business\"")
  end
  let(:codecommit_client) { instance_double(Dependabot::Clients::CodeCommit) }
  let(:branch_response) do
    client = Aws::CodeCommit::Client.new(stub_responses: true)
    client.stub_responses(
      :get_branch,
      branch: {
        branch_name: branch_name,
        commit_id: "base"
      }
    )
    client.get_branch(repository_name: source.repo, branch_name: branch_name)
  end
  let(:open_pull_requests) { [] }
  let(:closed_pull_requests) { [] }

  before do
    allow(Dependabot::Clients::CodeCommit)
      .to receive(:for_source).and_return(codecommit_client)
    allow(codecommit_client).to receive(:branch).with(branch_name).and_return(branch_response)
    allow(codecommit_client)
      .to receive(:pull_requests).with(source.repo, "open", branch_name)
      .and_return(open_pull_requests)
    allow(codecommit_client)
      .to receive(:pull_requests).with(source.repo, "closed", branch_name)
      .and_return(closed_pull_requests)
    allow(codecommit_client).to receive_messages(
      create_commit: Aws::CodeCommit::Types::CreateCommitOutput.new,
      create_pull_request: Aws::CodeCommit::Types::CreatePullRequestOutput.new
    )
  end

  context "when an open pull request has no merge metadata" do
    let(:open_pull_requests) { [pull_request_response] }

    it "treats the pull request as unmerged" do
      expect { creator.create }.not_to raise_error
      expect(codecommit_client).not_to have_received(:create_pull_request)
    end
  end

  context "when an open pull request has no merged flag" do
    let(:open_pull_requests) do
      [pull_request_response(merge_metadata: {})]
    end

    it "treats the pull request as unmerged" do
      expect { creator.create }.not_to raise_error
      expect(codecommit_client).not_to have_received(:create_pull_request)
    end
  end

  context "when the existing pull request was merged" do
    let(:closed_pull_requests) do
      [pull_request_response(merge_metadata: { is_merged: true })]
    end

    it "creates a new pull request" do
      creator.create

      expect(codecommit_client).to have_received(:create_commit)
      expect(codecommit_client).to have_received(:create_pull_request)
    end
  end

  def pull_request_response(merge_metadata: nil)
    client = Aws::CodeCommit::Client.new(stub_responses: true)
    target = {
      source_reference: "refs/heads/#{branch_name}",
      destination_reference: "refs/heads/main"
    }
    target[:merge_metadata] = merge_metadata if merge_metadata
    client.stub_responses(
      :get_pull_request,
      pull_request: {
        pull_request_id: "1",
        pull_request_targets: [target]
      }
    )
    client.get_pull_request(pull_request_id: "1")
  end
end
