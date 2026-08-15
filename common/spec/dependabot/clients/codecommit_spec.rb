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
      )
    end

    it "preserves the response wrapper and sorts commits by author date" do
      expect(commits).to be_a(Seahorse::Client::Response)
      expect(commits.data).to be_a(Aws::CodeCommit::Types::BatchGetCommitsOutput)
      expect(commits.data.commits.map(&:message)).to eq(%w(Newer Older))
    end
  end
end
