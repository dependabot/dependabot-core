# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/clients/codecommit"
require "dependabot/credential"

RSpec.describe Dependabot::Clients::CodeCommit do
  let(:branch) { "master" }
  let(:repo) { "gocardless" }
  let(:credentials) do
    [Dependabot::Credential.new(
      {
        "type" => "git_source",
        "region" => "us-east-1",
        "username" => "AWS_ACCESS_KEY_ID",
        "password" => "AWS_SECRET_ACCESS_KEY"
      }
    )]
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "codecommit",
      repo: "",
      directory: "/",
      branch: "master"
    )
  end
  let(:stubbed_cc_client) { Aws::CodeCommit::Client.new(stub_responses: true) }
  let(:client) do
    described_class.for_source(source: source, credentials: credentials)
  end

  before do
    allow_any_instance_of(
      described_class
    ).to receive(:cc_client).and_return(stubbed_cc_client)
  end

  describe "#fetch_commit" do
    subject(:fetch_commit) { client.fetch_commit(nil, branch) }

    context "when a response is returned" do
      before do
        stubbed_cc_client
          .stub_responses(
            :get_branch,
            branch:
              {
                branch_name: "master",
                commit_id: "9c8376e9b2e943c2c72fac4b239876f377f0305a"
              }
          )
      end

      specify { expect { fetch_commit }.not_to raise_error }

      it { is_expected.to eq("9c8376e9b2e943c2c72fac4b239876f377f0305a") }

      context "without credentials" do
        let(:credentials) { [] }

        before { ENV["AWS_REGION"] = "us-east-1" }

        it { is_expected.to eq("9c8376e9b2e943c2c72fac4b239876f377f0305a") }
      end
    end

    context "when the target branch does not exist" do
      before do
        stubbed_cc_client.stub_responses(
          :get_branch,
          "BranchDoesNotExistException"
        )
      end

      it "raises a helpful error" do
        expect { fetch_commit }.to raise_error(
          Aws::CodeCommit::Errors::BranchDoesNotExistException
        )
      end
    end
  end

  describe "#fetch_repo_contents" do
    subject(:repo_contents) { client.fetch_repo_contents(repo, branch, "/") }

    before do
      stubbed_cc_client.stub_responses(
        :get_folder,
        commit_id: branch,
        folder_path: "/",
        files: [{ relative_path: "Gemfile" }]
      )
    end

    it "preserves the response wrapper and typed folder payload" do
      expect(repo_contents).to be_a(Seahorse::Client::Response)
      expect(repo_contents.data).to be_a(Aws::CodeCommit::Types::GetFolderOutput)
      expect(repo_contents.data.files.map(&:relative_path)).to eq(["Gemfile"])
    end
  end

  describe "#commits" do
    subject(:commits) { client.commits(repo, branch) }

    let(:batch_get_commits_response) do
      {
        commits: [
          {
            commit_id: "older",
            author: {
              date: "2024-01-01T00:00:00Z",
              email: "support@dependabot.com"
            },
            message: "Older"
          },
          {
            commit_id: "newer",
            author: {
              date: "2025-01-01T00:00:00Z",
              email: "support@dependabot.com"
            },
            message: "Newer"
          }
        ]
      }
    end

    before do
      allow(Aws::CodeCommit::Client).to receive(:new).and_return(stubbed_cc_client)
      stubbed_cc_client.stub_responses(
        :get_branch,
        branch: {
          branch_name: branch,
          commit_id: "newer"
        }
      )
      stubbed_cc_client.stub_responses(
        :get_commit,
        [
          {
            commit: {
              commit_id: "newer",
              parents: ["older"]
            }
          },
          {
            commit: {
              commit_id: "older",
              parents: []
            }
          }
        ]
      )
      stubbed_cc_client.stub_responses(
        :batch_get_commits,
        batch_get_commits_response
      )
    end

    it "preserves the response wrapper and sorts commits by author date" do
      expect(commits).to be_a(Seahorse::Client::Response)
      expect(commits.data).to be_a(Aws::CodeCommit::Types::BatchGetCommitsOutput)
      expect(commits.data.commits.map(&:message)).to eq(%w(Newer Older))
    end

    context "when the response has no commits" do
      let(:batch_get_commits_response) { {} }

      it "preserves the empty response" do
        expect(commits.data.commits).to be_nil
      end
    end

    context "when a commit has no author" do
      let(:batch_get_commits_response) do
        {
          commits: [{ commit_id: "newer", message: "No author" }]
        }
      end

      it "does not fail while sorting" do
        expect(commits.data.commits.map(&:message)).to eq(["No author"])
      end
    end
  end

  describe "#pull_requests" do
    subject(:pull_requests) { client.pull_requests(repo, "open", branch_name) }

    let(:branch_name) { "dependabot/bundler/business-1.5.0" }

    before do
      allow(Aws::CodeCommit::Client).to receive(:new).and_return(stubbed_cc_client)
      stubbed_cc_client.stub_responses(
        :list_pull_requests,
        pull_request_ids: %w(matching other)
      )
      stubbed_cc_client.stub_responses(
        :get_pull_request,
        [
          {
            pull_request: {
              pull_request_id: "matching",
              pull_request_targets: [{
                source_reference: "refs/heads/#{branch_name}"
              }]
            }
          },
          {
            pull_request: {
              pull_request_id: "other",
              pull_request_targets: [{
                source_reference: "refs/heads/#{branch_name}-next"
              }]
            }
          }
        ]
      )
    end

    it "preserves matching pull request response wrappers" do
      expect(pull_requests.length).to eq(1)
      expect(pull_requests.first).to be_a(Seahorse::Client::Response)
      expect(pull_requests.first.data).to be_a(Aws::CodeCommit::Types::GetPullRequestOutput)
      expect(pull_requests.first.data.pull_request.pull_request_id).to eq("matching")
    end
  end
end
