# frozen_string_literal: true
require "octokit"
require "spec_helper"
require "bump/dependency"
require "bump/dependency_file"
require "bump/pull_request_updater"

RSpec.describe Bump::PullRequestUpdater do
  subject(:updater) do
    Bump::PullRequestUpdater.new(repo: repo,
                                 base_commit: base_commit,
                                 files: files,
                                 github_client: github_client,
                                 pull_request_number: pull_request_number)
  end

  let(:repo) { "gocardless/bump" }
  let(:files) { [gemfile, gemfile_lock] }
  let(:base_commit) { "basecommitsha" }
  let(:pull_request_number) { 1 }
  let(:github_client) { Octokit::Client.new(access_token: "token") }

  let(:gemfile) do
    Bump::DependencyFile.new(
      name: "Gemfile",
      content: fixture("ruby", "gemfiles", "Gemfile"),
      directory: "files/are/here"
    )
  end
  let(:gemfile_lock) do
    Bump::DependencyFile.new(
      name: "Gemfile.lock",
      content: fixture("ruby", "lockfiles", "Gemfile.lock"),
      directory: "files/are/here"
    )
  end

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:watched_repo_url) { "https://api.github.com/repos/#{repo}" }
  let(:pull_request_url) { watched_repo_url + "/pulls/#{pull_request_number}" }
  let(:business_repo_url) { "https://api.github.com/repos/gocardless/business" }
  let(:branch_name) { "bump/ruby/business-1.5.0" }

  before do
    stub_request(:get, pull_request_url).
      to_return(status: 200,
                body: fixture("github", "pull_request.json"),
                headers: json_header)
    stub_request(:post, "#{watched_repo_url}/git/trees").
      to_return(status: 200,
                body: fixture("github", "create_tree.json"),
                headers: json_header)
    stub_request(:post, "#{watched_repo_url}/git/commits").
      to_return(status: 200,
                body: fixture("github", "create_commit.json"),
                headers: json_header)
    stub_request(:patch, "#{watched_repo_url}/git/refs/heads/#{branch_name}").
      to_return(status: 200,
                body: fixture("github", "update_ref.json"),
                headers: json_header)
  end

  describe "#update" do
    it "pushes a commit to GitHub" do
      updater.update

      expect(WebMock).
        to have_requested(:post, "#{watched_repo_url}/git/trees").
        with(body: {
               base_tree: "basecommitsha",
               tree: [
                 {
                   path: "files/are/here/Gemfile",
                   mode: "100644",
                   type: "blob",
                   content: fixture("ruby", "gemfiles", "Gemfile")
                 },
                 {
                   path: "files/are/here/Gemfile.lock",
                   mode: "100644",
                   type: "blob",
                   content: fixture("ruby", "lockfiles", "Gemfile.lock")
                 }
               ]
             })

      expect(WebMock).
        to have_requested(:post, "#{watched_repo_url}/git/commits")
    end

    it "has the right commit message" do
      updater.update

      expect(WebMock).
        to have_requested(:post, "#{watched_repo_url}/git/commits").
        with(body: {
               parents: ["basecommitsha"],
               tree: "cd8274d15fa3ae2ab983129fb037999f264ba9a7",
               message: /Bump business to 1\.5\.0\n\nBumps \[business\]/
             })
    end

    it "updates the PR's branch to point to that commit" do
      updater.update

      expect(WebMock).
        to have_requested(
          :patch, "#{watched_repo_url}/git/refs/heads/#{branch_name}"
        ).with(
          body: {
            sha: "7638417db6d59f3c431d3e1f261cc637155684cd",
            force: true
          }
        )
    end

    it "returns details of the updated branch" do
      expect(updater.update.object.sha).
        to eq("1e2d2afe8320998baecdfe127a49dca9a6650e07")
    end
  end
end
