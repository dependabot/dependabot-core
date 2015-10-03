require "spec_helper"
require "bumper/dependency"
require "bumper/dependency_file"
require "bumper/pull_request_creator/pull_request_creator"

RSpec.describe PullRequestCreator do

  let(:gemfile) do
    DependencyFile.new(
      name: "Gemfile",
      content: fixture("Gemfile")
    )
  end

  let(:repo) { "gocardless/bump" }
  let(:github_headers) { {"Content-Type": "application/json"} }
  let(:repo_response) { github_fixture("repo.json") }
  let(:ref_response) { github_fixture("ref.json") }
  let(:create_ref_response) { github_fixture("create_ref.json") }
  let(:update_file_response) { github_fixture("update_file.json") }
  let(:create_pr_response) { github_fixture("create_pr.json") }
  let(:gemfile_content) { github_fixture("gemfile_content.json") }

  let(:creator) do
    PullRequestCreator.new(
      repo: repo,
      dependency: Dependency.new(name: "test", version: "0.0.1"),
      files: [gemfile]
    )
  end

  before do
    stub_request(:get, "https://api.github.com/repos/#{repo}").
         to_return(status: 200, body: repo_response, headers: github_headers)

    stub_request(:get, "https://api.github.com/repos/#{repo}/git/refs/heads/master").
         to_return(:status => 200, body: ref_response, headers: github_headers)

    stub_request(:post, "https://api.github.com/repos/#{repo}/git/refs").
         to_return(:status => 200, body: create_ref_response, :headers => github_headers)

    stub_request(:get, "https://api.github.com/repos/gocardless/bump/contents/Gemfile").
         to_return(:status => 200, body: gemfile_content, headers: github_headers)

    stub_request(:put, "https://api.github.com/repos/gocardless/bump/contents/Gemfile").
         to_return(:status => 200, body: update_file_response, headers: github_headers)

    stub_request(:post, "https://api.github.com/repos/gocardless/bump/pulls").
         to_return(:status => 200, body: create_pr_response, headers: github_headers)
  end

  # describe "information" do
  #   its("new_branch_name") { is_expected.to eq("bump_test_to_0.0.1") }
  # end

  subject(:pr) { creator.create }

  it { is_expected.to be_a(Sawyer::Resource) }

  describe "requests" do
    before { creator.create }
    subject { WebMock }

    describe "get repo info" do
      it { is_expected.to have_requested(:get, "https://api.github.com/repos/#{repo}") }
    end

    describe "get default branch ref" do
      it { is_expected.to have_requested(:get, "https://api.github.com/repos/#{repo}/git/refs/heads/master") }
    end

    describe "cut new branch" do
      it do
        is_expected.to have_requested(:post, "https://api.github.com/repos/#{repo}/git/refs").
          with(:body => {
            ref: "refs/heads/bump_test_to_0.0.1",
            sha: "aa218f56b14c9653891f9e74264a383fa43fefbd"
          })
      end
    end

    describe "get file content" do
      it { is_expected.to have_requested(:get, "https://api.github.com/repos/gocardless/bump/contents/Gemfile") }
    end

    describe "update file content" do
      it do
        is_expected.to have_requested(:put,  "https://api.github.com/repos/gocardless/bump/contents/Gemfile").
          with(:body => {
            branch:"bump_test_to_0.0.1",
            sha:"dbce0c9e2e7efd19139c2c0aeb0110e837812c2f",
            content:"c291cmNlICJodHRwczovL3J1YnlnZW1zLm9yZyIKCmdlbSAiYnVzaW5lc3MiLCAifj4gMS40LjAiCg==",
            message:"Updating Gemfile"
          })
      end
    end

    describe "creates pull request" do
      it do
        is_expected.to have_requested(:post, "https://api.github.com/repos/gocardless/bump/pulls").
          with(:body => {
            base: "master",
            head: "bump_test_to_0.0.1",
            title: "Bump test to 0.0.1",
            body: "<3 bump"
          })
      end
    end
  end
end
