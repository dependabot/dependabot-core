# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/pull_request_updater/azure"

RSpec.describe Dependabot::PullRequestUpdater::Azure do
  subject(:updater) do
    described_class.new(
      source: source,
      base_commit: base_commit,
      old_commit: old_commit,
      files: files,
      credentials: credentials,
      pull_request_number: pull_request_number,
      author_details: author_details
    )
  end

  let(:org) { "org" }
  let(:project) { "project" }
  let(:repo_name) { "repo" }
  let(:source) do
    Dependabot::Source.new(provider: "azure", repo: "#{org}/#{project}/_git/#{repo_name}")
  end
  let(:files) { [gemfile, gemspec] }
  let(:base_commit) { "basecommitsha" }
  let(:old_commit) { "oldcommitsha" }
  let(:source_branch_old_commit) { "9c8376e9b2e943c2c72fac4b239876f377f0305a" }
  let(:source_branch_new_commit) { "newcommitsha" }
  let(:tree_object_id) { "treeobjectid" }
  let(:pull_request_number) { 1 }
  let(:author_details) { nil }
  let(:source_branch) { "dependabot/npm_and_yarn/business-1.5.0" }
  let(:temp_branch) { source_branch + "-temp" }
  let(:path) { "files/are/here" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "dev.azure.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  let(:gemfile) do
    Dependabot::DependencyFile.new(
      name: "Gemfile",
      content: fixture("ruby", "gemfiles", "Gemfile"),
      directory: path
    )
  end
  let(:gemspec) do
    Dependabot::DependencyFile.new(
      name: "test.gemspec",
      content: fixture("ruby", "gemspecs", "example"),
      directory: path
    )
  end

  let(:commit_message) { "Added example file" }
  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:source_api_endpoint) { "https://dev.azure.com" }
  let(:repo_url) { "#{source_api_endpoint}/#{org}/#{project}/_apis/git/repositories/#{repo_name}" }
  let(:pull_request_url) { "#{source_api_endpoint}/#{org}/#{project}/_apis/git/pullrequests/#{pull_request_number}" }
  let(:source_branch_url) { repo_url + "/refs?filter=heads/#{source_branch}" }
  let(:source_branch_commits_url) { repo_url + "/commits?searchCriteria.itemVersion.version=#{source_branch}" }
  let(:repo_contents_tree_url) do
    repo_url + "/items?path=/#{path}&versionDescriptor.version=#{base_commit}&versionDescriptor.versionType=commit"
  end
  let(:repo_contents_url) { repo_url + "/trees/#{tree_object_id}?recursive=false" }
  let(:create_commit_url) { repo_url + "/pushes?api-version=5.0" }
  let(:branch_update_url) { repo_url + "/refs?api-version=5.0" }

  before do
    stub_request(:get, pull_request_url).
      to_return(status: 200,
                body: fixture("azure", "pull_request_details.json"),
                headers: json_header)
    stub_request(:get, source_branch_url).
      to_return(status: 200,
                body: fixture("azure", "pull_request_source_branch_details.json"),
                headers: json_header)
    stub_request(:post, create_commit_url).
      to_return(status: 201,
                body: fixture("azure", "create_new_branch.json"),
                headers: json_header)
    stub_request(:get, source_branch_commits_url).
      to_return(status: 200,
                body: fixture("azure", "commits.json"),
                headers: json_header)
    stub_request(:get, repo_contents_tree_url).
      to_return(status: 200,
                body: fixture("azure", "repo_contents_treeroot.json"),
                headers: json_header)
    stub_request(:get, repo_contents_url).
      to_return(status: 200,
                body: fixture("azure", "repo_contents.json"),
                headers: json_header)
    stub_request(:post, branch_update_url).
      to_return(status: 201,
                body: fixture("azure", "update_ref.json"))
  end

  describe "#update" do
    context "when the PR doesn't exist" do
      before { stub_request(:get, pull_request_url).to_return(status: 404) }

      it "doesn't update source branch head commit in AzureDevOps" do
        updater.update
        expect(WebMock).
          to_not have_requested(:post, branch_update_url)
      end

      it "returns nil" do
        expect(updater.update).to be_nil
      end
    end

    context "when the branch doesn't exist" do
      before { stub_request(:get, source_branch_url).to_return(status: 404) }

      it "doesn't update source branch head commit in AzureDevOps" do
        updater.update
        expect(WebMock).
          to_not have_requested(:post, branch_update_url)
      end

      it "returns nil" do
        expect(updater.update).to be_nil
      end
    end

    context "when updating source branch head commit in AzureDevOps" do
      before do
        allow(updater).to receive(:temp_branch_name).and_return(temp_branch)
      end

      it "commits on the temp branch" do
        updater.update

        expect(WebMock).
          to(
            have_requested(:post, create_commit_url).
            with(body: {
              refUpdates: [
                { name: "refs/heads/#{temp_branch}", oldObjectId: base_commit }
              ],
              commits: [
                {
                  comment: commit_message,
                  changes: files.map do |file|
                    {
                      changeType: "edit",
                      item: { path: file.path },
                      newContent: {
                        content: Base64.encode64(file.content),
                        contentType: "base64encoded"
                      }
                    }
                  end
                }
              ]
            })
          )
      end

      it "sends request to AzureDevOps to update source branch head commit" do
        allow(updater).to receive(:temp_branch_name).and_return(temp_branch)
        updater.update

        expect(WebMock).
          to(
            have_requested(:post, branch_update_url).
                with(body: [
                  { name: "refs/heads/#{source_branch}", oldObjectId: source_branch_old_commit,
                    newObjectId: source_branch_new_commit }
                ].to_json)
          )
      end

      it "raises a helpful error when source branch update is unsuccessful" do
        stub_request(:post, branch_update_url).
          to_return(status: 200, body: fixture("azure", "update_ref_failed.json"))

        expect { updater.update }.to raise_error(Dependabot::PullRequestUpdater::Azure::PullRequestUpdateFailed)
      end
    end

    context "with author details provided" do
      let(:author_details) do
        { email: "support@dependabot.com", name: "dependabot" }
      end

      it "includes the author details when commiting on the temp branch" do
        updater.update

        expect(WebMock).
          to(
            have_requested(:post, create_commit_url).
              with do |req|
                json_body = JSON.parse(req.body)
                expect(json_body.fetch("commits").count).to eq(1)
                expect(json_body.fetch("commits").first.fetch("author")).
                  to eq(author_details.transform_keys(&:to_s))
              end
          )
      end
    end
  end
end
