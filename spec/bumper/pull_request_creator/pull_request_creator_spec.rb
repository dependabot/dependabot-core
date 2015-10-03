require "spec_helper"
require "bumper/dependency"
require "bumper/dependency_file"
require "bumper/pull_request_creator/pull_request_creator"

RSpec.describe PullRequestCreator do
  subject(:creator) do
    PullRequestCreator.new(repo: repo, dependency: dependency, files: files)
  end

  let(:dependency) { Dependency.new(name: "business", version: "1.5.0") }
  let(:repo) { "gocardless/bump" }
  let(:files) { [gemfile] }

  let(:gemfile) do
    DependencyFile.new(name: "Gemfile", content: fixture("Gemfile"))
  end

  let(:github_headers) { { "Content-Type": "application/json" } }
  let(:repo_response) { fixture("github", "repo.json") }
  let(:ref_response) { fixture("github", "ref.json") }
  let(:create_ref_response) { fixture("github", "create_ref.json") }
  let(:update_file_response) { fixture("github", "update_file.json") }
  let(:create_pr_response) { fixture("github", "create_pr.json") }
  let(:gemfile_content_response) { fixture("github", "gemfile_content.json") }

  before do
    stub_request(:get, "https://api.github.com/repos/#{repo}").
      to_return(status: 200, body: repo_response, headers: github_headers)
    stub_request(:get, "https://api.github.com/repos/#{repo}/git/refs/heads/master").
      to_return(status: 200, body: ref_response, headers: github_headers)
    stub_request(:post, "https://api.github.com/repos/#{repo}/git/refs").
      to_return(status: 200, body: create_ref_response, headers: github_headers)
    stub_request(:get, "https://api.github.com/repos/#{repo}/contents/#{gemfile.name}").
      to_return(status: 200, body: gemfile_content_response, headers: github_headers)
    stub_request(:put, "https://api.github.com/repos/#{repo}/contents/#{gemfile.name}").
      to_return(status: 200, body: update_file_response, headers: github_headers)
    stub_request(:post, "https://api.github.com/repos/#{repo}/pulls").
      to_return(status: 200, body: create_pr_response, headers: github_headers)
  end

  describe "#create" do
    it "creates a branch with the right name" do
      creator.create

      expect(WebMock).
        to have_requested(:post, "https://api.github.com/repos/gocardless/bump/git/refs").
        with(body: {
          ref: "refs/heads/bump_business_to_1.5.0",
          sha: "aa218f56b14c9653891f9e74264a383fa43fefbd"
        })
    end

    it "pushes changes to that branch" do
      creator.create

      expect(WebMock).
        to have_requested(:put, "https://api.github.com/repos/gocardless/bump/contents/Gemfile").
        with(body: {
          branch:"bump_business_to_1.5.0",
          sha:"dbce0c9e2e7efd19139c2c0aeb0110e837812c2f",
          content:"c291cmNlICJodHRwczovL3J1YnlnZW1zLm9yZyIKCmdlbSAiYnVzaW5lc3MiLCAifj4gMS40LjAiCg==",
          message:"Updating Gemfile"
        })
    end

    it "creates a PR with the right details" do
      creator.create

      expect(WebMock).
        to have_requested(:post, "https://api.github.com/repos/gocardless/bump/pulls").
        with(body: {
          base: "master",
          head: "bump_business_to_1.5.0",
          title: "Bump business to 1.5.0",
          body: "<3 bump"
        })
    end
  end
end
